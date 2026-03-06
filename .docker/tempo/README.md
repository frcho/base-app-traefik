# Tempo Configuration Guide

## Overview

Tempo stores distributed traces from the SentinelX microservices platform. This guide explains the key configuration parameters and their impact on trace visibility and retention.

## Configuration Files

- **`tempo-config.yaml`**: Development configuration (current active)
- **`tempo-config.prod.yaml`**: Production configuration template

## Key Parameters

### Ingester Settings

#### `trace_idle_period`
Time to keep incomplete traces in memory before discarding them.

- **Dev**: `10s` - Discards traces that don't receive new spans within 10 seconds
- **Prod**: `2h` - Handles long-running async operations
- **Impact**: Traces that don't complete within this period are lost

**CRITICAL:** Must be **shorter** than `max_block_duration` to prevent traces from being discarded before they're written to disk. If `trace_idle_period > max_block_duration`, completed traces may be removed from WAL before the block flushes, causing logs to have `trace_id` but traces to be missing in Tempo.

**Recommended ratio:** `trace_idle_period` should be at least 10x shorter than `max_block_duration`.

#### `max_block_duration`
How often traces are flushed from memory to disk blocks.

- **Dev**: `2m` - Fast visibility in Grafana (traces appear every 2 minutes)
- **Prod**: `5m` - Reduces I/O overhead while maintaining good visibility
- **Impact**: Lower = faster trace visibility, higher I/O load

### Storage Settings

#### `block.retention`
How long completed trace blocks are kept before deletion.

- **Dev**: `24h` - 1 day retention (saves disk space)
- **Prod**: `168h` - 7 days retention (compliance and debugging)
- **Impact**: Automatic cleanup prevents disk from filling up

### Metrics Generator

#### `service_graphs.wait`
Time to wait for all spans before building service dependency graph.

- **Dev**: `10s` - Quick feedback
- **Prod**: `30s` - More accurate graphs for distributed traces

#### `max_items`
Maximum number of unique service pairs tracked.

- **Dev**: `10000` - Sufficient for small deployments
- **Prod**: `100000` - Handles high-cardinality service meshes

#### Processors
- **`service-graphs`**: Generates service dependency maps
- **`span-metrics`**: Creates RED metrics (Rate, Errors, Duration)
- **`local-blocks`**: Required for TraceQL metrics queries in Grafana

## Trace Visibility Behavior

### Why traces appear delayed

Traces are buffered in memory (WAL) and written to disk in blocks based on `max_block_duration`:

1. **Request completes** → Trace sent to Tempo
2. **Trace stored in WAL** → Held in memory
3. **Block closes** (after `max_block_duration`) → Written to disk
4. **Trace visible in Grafana** → Can be queried

**Example with `max_block_duration: 5m`:**
- Event at 13:31 → Trace visible at 13:35 (next block close)
- Event at 13:34 → Trace visible at 13:35 (same block)
- Event at 13:36 → Trace visible at 13:40 (next block)

### Incomplete traces

Traces are discarded if they don't complete within `trace_idle_period`:

- **Cause**: Service crashes, network issues, or genuinely long operations
- **Symptom**: Logs show `trace_id` but trace doesn't exist in Tempo
- **Solution**: Increase `trace_idle_period` or investigate why traces aren't completing

## Switching to Production Config

### Option 1: Replace file
```bash
cd /traefik/.docker/tempo
cp tempo-config.yaml tempo-config.dev.yaml  # Backup
cp tempo-config.prod.yaml tempo-config.yaml
docker restart traefik-tempo
```

### Option 2: Update compose.yaml
```yaml
tempo:
  volumes:
    - ./tempo/tempo-config.prod.yaml:/etc/tempo-config.yaml:ro
```

## Monitoring

### Check Tempo health
```bash
docker logs traefik-tempo --tail 50
```

### Verify trace ingestion
```bash
docker logs traefik-tempo | grep -i "ingester\|compaction"
```

### Check storage usage
```bash
docker exec traefik-tempo du -sh /var/tempo/traces
```

## Troubleshooting

### Traces not appearing
1. Check `max_block_duration` - wait at least this long
2. Verify Alloy is sending traces: `docker logs traefik-alloy | grep -i trace`
3. Check Tempo errors: `docker logs traefik-tempo | grep -i error`

### Traces disappearing
1. Check `trace_idle_period` vs `max_block_duration` - idle period must be shorter
2. Verify `block.retention` - traces older than this are deleted
3. Check disk space: `df -h`
4. Ensure `trace_idle_period` is sufficient for your slowest operations

**Common issue:** If `trace_idle_period: 1h` and `max_block_duration: 2m`, traces complete but sit in WAL for up to 2 minutes. If they're marked "idle" during that time, they're discarded before being written to disk. Logs will show `trace_id` but Tempo won't have the trace.

### "local-blocks processor not found" error
Ensure `local-blocks` is in the `processors` list under `overrides.defaults.metrics_generator`.

## Performance Tuning

### High trace volume (>1000 traces/min)
- Increase `max_block_duration` to `10m` (reduces I/O)
- Increase `max_items` to `500000`
- Consider using S3/GCS backend instead of local storage

### Low latency requirements (need traces immediately)
- Reduce `max_block_duration` to `1m`
- Accept higher I/O overhead
- Monitor disk I/O with `iostat`

### Disk space constraints
- Reduce `block.retention` to `48h` or `72h`
- Implement sampling in Alloy (not currently configured)
- Use external storage backend

## Related Documentation

- [Grafana Alloy Configuration](../alloy/README.md) - Log and trace collection
- [Loki-Tempo Correlation](../grafana/provisioning/datasources/README.md) - Trace links in logs
- [OpenTelemetry Setup](../../../docs/OBSERVABILITY_SETUP.md) - PHP instrumentation
