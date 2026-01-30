# Maintenance Notification Templates

## Pre-Migration Announcement (1 Week Before)

```
Subject: [Scheduled] RabbitMQ Cluster Upgrade - [DATE]

Team,

We are scheduling a RabbitMQ cluster upgrade from version 3.12 to 4.1.4.

**Scheduled Date:** [DATE]
**Maintenance Window:** [START TIME] - [END TIME] [TIMEZONE]
**Expected Impact:** Minimal to None (zero-downtime migration planned)

## What's Changing
- RabbitMQ version upgrade (3.12 → 4.1.4)
- Queue type migration (Classic → Quorum for improved durability)
- Enhanced monitoring and reliability features

## Expected Impact
- No service interruption expected
- Brief message delays possible during cutover (< 5 minutes)
- Applications may experience brief reconnection events

## Action Required
- Review your application's RabbitMQ client library version
- Ensure connection retry logic is implemented
- Contact [TEAM] if you have concerns about specific queues

## Timeline
- [DATE -7 days]: Pre-migration testing complete
- [DATE -1 day]: Final backup and verification
- [DATE]: Migration execution
- [DATE +1 day]: Post-migration validation

## Contacts
- Migration Lead: [NAME] - [EMAIL]
- On-Call: [PAGER]
- Slack: #rabbitmq-migration

Please reply to this email if you have questions or concerns.

[NAME]
Platform Team
```

---

## Migration Day Notification (Start)

```
Subject: [STARTING] RabbitMQ Cluster Upgrade in Progress

Team,

We are beginning the RabbitMQ cluster upgrade.

**Start Time:** [TIME] [TIMEZONE]
**Status:** In Progress
**Expected Duration:** [X] hours

## Current Phase
- [ ] Phase 1: Configure message bridge
- [ ] Phase 2: Migrate non-critical applications
- [ ] Phase 3: Migrate critical applications
- [ ] Phase 4: Traffic cutover
- [ ] Phase 5: Validation

## Monitoring
- Status updates every 30 minutes
- Real-time status: [DASHBOARD URL]

## If You Experience Issues
- Check: [STATUS PAGE URL]
- Contact: [EMERGENCY CONTACT]
- Slack: #rabbitmq-migration

[NAME]
Migration Lead
```

---

## Migration Day Notification (Complete - Success)

```
Subject: [COMPLETE] RabbitMQ Cluster Upgrade Successful

Team,

The RabbitMQ cluster upgrade has been completed successfully.

**Completion Time:** [TIME] [TIMEZONE]
**Duration:** [X] hours
**Status:** ✓ Success

## Summary
- RabbitMQ version: 4.1.4
- All queues migrated to quorum type
- Zero message loss confirmed
- All applications connected and operational

## New Features Available
- Improved durability with Raft-based replication
- Automatic leader election
- Poison message handling with delivery limits

## What to Expect
- Performance should be equivalent or better
- No changes required to your applications
- Enhanced monitoring available in Grafana

## Post-Migration Support
- 24/7 monitoring active for next 48 hours
- Report any issues to: [CONTACT]
- Slack: #rabbitmq-migration

Thank you for your patience during this upgrade.

[NAME]
Platform Team
```

---

## Migration Day Notification (Rollback)

```
Subject: [ALERT] RabbitMQ Upgrade Rolled Back

Team,

We have initiated a rollback of the RabbitMQ cluster upgrade.

**Rollback Time:** [TIME] [TIMEZONE]
**Current Status:** Operating on previous version (3.12)
**Impact:** Minimal - services restored

## What Happened
[Brief description of issue that triggered rollback]

## Current State
- Cluster: Operational on version 3.12
- Message flow: Normal
- Applications: Connected

## Next Steps
1. Root cause analysis in progress
2. Post-mortem scheduled for [DATE]
3. Retry date TBD

## Action Required
- No action required from application teams
- Report any issues to: [CONTACT]

We apologize for any inconvenience. Updates will follow.

[NAME]
Migration Lead
```

---

## Blue Cluster Decommission Notice

```
Subject: [Notice] Legacy RabbitMQ Cluster Decommissioning - [DATE]

Team,

Following the successful migration, we will be decommissioning the legacy
RabbitMQ cluster (blue cluster).

**Decommission Date:** [DATE]
**Final Backup:** Completed and archived

## Details
- Old cluster: rabbit-blue-1,2,3 will be shut down
- All traffic now on: rabbit-green-1,2,3
- DNS entries will be updated/removed

## Action Required
- Verify no hardcoded references to old cluster hosts
- Update any documentation referencing old cluster
- Contact [TEAM] if you have dependencies on old cluster

## Archive
- Cluster definitions: Archived for 90 days
- Logs: Archived for 30 days
- Configuration: Documented in Confluence

Questions? Contact [NAME] or post in #rabbitmq-migration.

[NAME]
Platform Team
```

---

## Slack Message Templates

### Migration Start
```
:rabbitmq: *RabbitMQ Migration Starting*
━━━━━━━━━━━━━━━━━━━━━━━━
:clock1: Start: [TIME]
:target: Goal: Upgrade to 4.1.4 + Quorum Queues
:eyes: Dashboard: [URL]

Updates every 30 min. Questions → this thread.
```

### Phase Update
```
:rabbitmq: *Migration Update*
━━━━━━━━━━━━━━━━━━━━━━━━
:white_check_mark: Phase 1: Complete
:arrow_right: Phase 2: In Progress
:hourglass_flowing_sand: Phase 3: Pending
:hourglass_flowing_sand: Phase 4: Pending
```

### Migration Complete
```
:rabbitmq: :tada: *Migration Complete!*
━━━━━━━━━━━━━━━━━━━━━━━━
:white_check_mark: RabbitMQ 4.1.4 operational
:white_check_mark: All queues migrated
:white_check_mark: Zero message loss
:white_check_mark: Performance nominal

Thanks everyone! :clap:
```

### Rollback Alert
```
:rotating_light: *RabbitMQ Migration Rollback*
━━━━━━━━━━━━━━━━━━━━━━━━
:warning: Issue detected, rolling back
:arrow_right: Switching to blue cluster
:eyes: Stand by for updates

DO NOT restart applications yet.
```
