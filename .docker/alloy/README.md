# Grafana Alloy Configuration

Grafana Alloy is a telemetry collector that gathers logs from Docker containers and sends them to Loki with structured metadata and intelligent filtering.

## Overview

Alloy replaces the traditional Promtail + Loki setup with a more flexible pipeline that:
- Discovers Docker containers automatically
- Parses Monolog JSON logs
- Extracts trace context for distributed tracing
- Filters noise before sending to Loki
- Enriches logs with labels for better querying

## Architecture

```
Docker Containers
    ↓ (unix socket)
discovery.docker
    ↓
discovery.relabel (extract container metadata)
    ↓
loki.source.docker
    ↓
loki.process (JSON parsing, filtering, labeling)
    ↓
loki.write → Loki
```

## Key Features

- **Docker log collection** via Unix socket (`/var/run/docker.sock`)
- **JSON parsing** for Monolog format logs
- **Intelligent filtering** to reduce noise and storage costs
- **Trace context extraction** for correlation with Tempo traces
- **Label enrichment** from both Docker metadata and log content

## Configuration Components

### 1. Docker Discovery

```hcl
discovery.docker "containers" {
  host             = "unix:///var/run/docker.sock"
  refresh_interval = "10s"
}
```

Automatically discovers all running Docker containers every 10 seconds. Provides metadata like:
- Container name
- Container ID
- Docker labels (compose project, service name, etc.)

### 2. Relabeling

```hcl
discovery.relabel "containers_relabel" {
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}
```

Extracts the container name (removes leading `/`) and creates a `container` label. This label is later dropped to avoid conflicts with `service_name`.

### 3. Log Source

```hcl
loki.source.docker "containers" {
  host         = "unix:///var/run/docker.sock"
  targets      = discovery.docker.containers.targets
  relabel_rules = discovery.relabel.containers_relabel.rules
  forward_to   = [loki.process.production_logs.receiver]
}
```

Collects logs from discovered containers and forwards them to the processing pipeline.

### 4. Log Processing Pipeline

The `loki.process` component applies multiple stages in order:

#### Stage 1: JSON Parsing
```hcl
stage.json {
  expressions = {
    message      = "message",
    level        = "level_name",
    channel      = "channel",
    datetime     = "datetime",
    service_name = "extra.service",
    trace_id     = "extra.trace_id",
    span_id      = "extra.span_id",
    environment  = "extra.environment",
    http_method  = "context.http_method",
    http_status  = "context.http_status",
  }
  drop_malformed = false
}
```

Extracts fields from Monolog JSON format. Non-JSON logs are kept (not dropped).

#### Stage 2: Timestamp Parsing
```hcl
stage.timestamp {
  source = "datetime"
  format = "RFC3339"
  action_on_failure = "skip"
}
```

Parses the timestamp from Monolog's `datetime` field. If parsing fails, uses the current time.

#### Stage 3: Content Filtering
```hcl
stage.drop {
  source     = "message"
  expression = ".*(GET /health|GET /metrics|GET /ping|healthcheck).*"
}

stage.drop {
  source     = "channel"
  expression = "deprecation"
}
```

Drops logs by message content or channel to reduce noise.

#### Stage 4: Label Management
```hcl
stage.label_drop {
  values = ["container"]
}

stage.labels {
  values = {
    service_name = "service_name",
    level        = "level",
    channel      = "channel",
  }
}
```

Removes Docker's `container` label and adds labels from parsed JSON fields.

#### Stage 5: Structured Fields
```hcl
stage.output {
  source = "trace_id"
}
```

Exposes `trace_id` as a structured field (not a label) to avoid high cardinality issues.

#### Stage 6: Selective Filtering
```hcl
stage.match {
  selector = "{channel=\"console\", level!=\"ERROR\"}"
  action   = "drop"
}

stage.match {
  selector = "{channel=\"doctrine\", level!=\"ERROR\"}"
  action   = "drop"
}
```

Filters logs by label selectors. Applied AFTER labels are created so selectors work correctly.

### 5. Loki Writer

```hcl
loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

Sends processed logs to Loki.

## Label Extraction

### From Docker Discovery
- `container`: Container name (dropped before JSON labels)

### From Monolog JSON
- `service_name`: Extracted from `extra.service` field
- `level`: Log level (ERROR, WARNING, INFO, etc.)
- `channel`: Monolog channel (app, doctrine, console, etc.)

### Structured Fields (not labels)
- `trace_id`: From `extra.trace_id` - used for Tempo correlation
- `span_id`: From `extra.span_id`

## Critical: service_name Label

**The `service_name` label is REQUIRED for Tempo → Loki correlation.**

When you click "Logs for this span" in Grafana Tempo, it searches Loki using:
- `service_name` label (from span's `resource.service.name`)
- `trace_id` filter
- Time range around the span

### Configuration Flow

1. **Monolog** logs include `extra.service` field (from ServiceContextProcessor)
2. **Alloy** extracts it as `service_name` label:
   ```hcl
   stage.json {
     expressions = {
       service_name = "extra.service",
       // ...
     }
   }
   
   // Drop Docker's container label to avoid conflicts
   stage.label_drop {
     values = ["container"]
   }
   
   stage.labels {
     values = {
       service_name = "service_name",
       // ...
     }
   }
   ```
3. **Loki** stores logs with `service_name` label
4. **Tempo** spans have `resource.service.name` attribute (from `OTEL_SERVICE_NAME`)
5. **Grafana** maps `service.name` → `service_name` for log queries

### Without service_name

If `service_name` is missing:
- ❌ "Logs for this span" button won't find logs
- ❌ Grafana can't filter logs by service
- ✅ Trace_id links still work (but show logs from all services)

## Filtering Strategy

Logs are filtered to reduce noise while keeping important information:

### By Message Content
- Healthcheck endpoints (`/health`, `/metrics`, `/ping`)

### By Channel
- `deprecation` channel (PHP deprecation warnings)

### By Channel + Level
- `console` channel: Only ERROR level
- `doctrine` channel: Only ERROR level

**Important**: Filters are applied AFTER labels are created, so selectors work correctly.

## Trace Context

Trace IDs are extracted as structured fields (not labels) to avoid high cardinality:

```hcl
stage.output {
  source = "trace_id"
}
```

This allows:
- Full-text search for trace IDs
- Derived fields in Grafana to create "View Trace" links
- Lower cardinality than using trace_id as a label

## Troubleshooting

### service_name shows container name instead of service
- Check that `extra.service` exists in Monolog JSON
- Verify `stage.label_drop` removes `container` label before `stage.labels`
- Ensure ServiceContextProcessor is registered in Monolog

### "Logs for this span" doesn't work
- Verify `service_name` label exists in Loki
- Check that `OTEL_SERVICE_NAME` matches the service name in logs
- Confirm `tracesToLogs` is configured in Grafana datasource

### Logs not appearing in Loki
- Check Alloy logs: `docker logs traefik-alloy`
- Verify JSON parsing: Look for malformed JSON errors
- Test Loki query: `{service_name="email-delivery-service"}`

### High cardinality warnings
- Never use `trace_id` or `span_id` as labels (use `stage.output` instead)
- Avoid using high-cardinality fields like user IDs or request IDs as labels
- Use structured fields for searchable but high-cardinality data

### Filters not working
- Ensure `stage.labels` is called BEFORE `stage.match`
- Check regex patterns in `stage.drop` expressions
- Verify label selectors use correct syntax: `{label="value"}`

## Performance Considerations

### Label Cardinality
Labels create unique log streams in Loki. High cardinality = more streams = higher memory usage.

**Good labels** (low cardinality):
- `service_name` (~10 values)
- `level` (5-6 values)
- `channel` (~20 values)
- `environment` (3-4 values)

**Bad labels** (high cardinality):
- `trace_id` (millions of unique values)
- `user_id` (thousands of unique values)
- `request_id` (millions of unique values)

Use `stage.output` for high-cardinality fields to make them searchable without creating labels.

### Filtering Strategy
Filters reduce:
- Network bandwidth to Loki
- Storage costs
- Query latency

Apply filters early in the pipeline, but AFTER creating labels so selectors work.

### Refresh Interval
`refresh_interval = "10s"` balances:
- Fast discovery of new containers
- Low overhead on Docker API

Increase to 30s-60s if you have many containers and don't need instant discovery.

## Integration with Tempo

### Required Configuration

**In Monolog (ServiceContextProcessor):**
```php
$record['extra']['service'] = $_ENV['OTEL_SERVICE_NAME'];
$record['extra']['trace_id'] = $span->getContext()->getTraceId();
$record['extra']['span_id'] = $span->getContext()->getSpanId();
```

**In Alloy (this file):**
```hcl
stage.json {
  expressions = {
    service_name = "extra.service",
    trace_id     = "extra.trace_id",
    span_id      = "extra.span_id",
  }
}

stage.labels {
  values = {
    service_name = "service_name",
  }
}

stage.output {
  source = "trace_id"
}
```

**In Grafana (datasources.yml):**
```yaml
- name: Loki
  jsonData:
    derivedFields:
      - datasourceName: Tempo
        matcherRegex: "trace_id[\"\\s]*(?:=>|:|=)[\"\\s]*([a-f0-9]{32})"
        name: TraceID
        url: "/explore?..."
        urlDisplayLabel: "View Trace"

- name: Tempo
  jsonData:
    tracesToLogs:
      datasourceName: Loki
      filterByTraceID: true
```

This creates bidirectional navigation:
- **Loki → Tempo**: Click "View Trace" link in logs
- **Tempo → Loki**: Click "Logs for this span" in traces

## Configuration Files

- **Main config**: `/traefik/.docker/alloy/config.alloy`
- **Docker Compose**: `/traefik/docker-compose.yml` (alloy service)
- **Volume mount**: `/var/run/docker.sock` (read-only)

## Useful Commands

```bash
# Restart Alloy
docker restart traefik-alloy

# View Alloy logs
docker logs traefik-alloy --tail 100 -f

# Check if Alloy is discovering containers
docker logs traefik-alloy | grep -i discovery

# Test Loki query
curl -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={service_name="email-delivery-service"}' \
  --data-urlencode 'limit=10'

# Check Alloy health
docker exec traefik-alloy wget -qO- http://localhost:12345/metrics
```
