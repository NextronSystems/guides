# How to Integrate Valhalla Sigma Rules into Sekoia

The Nextron Valhalla Sigma Rules integration copies the Sigma rules from Nextron's Valhalla feed into your Sekoia Rules Catalog and keeps them up to date. This guide covers setup, every setting, and what to do once the rules are in your catalog.

The integration is for customers of both Sekoia and Nextron Valhalla. The one exception is the free Valhalla community feed: it only needs a Sekoia account.

## 1. Before you start

You need two API keys.

**Sekoia API key.** Log in to Sekoia, open **Settings → Workspace → API Keys**, create a key and give it these permissions:

| Permission | Needed for |
|---|---|
| *Manage rules and alert filters* | Creating, updating and disabling rules. Required. |
| *View Rules Catalog* | Reading the rules that are already in the catalog. Required. |
| *View intelligence with limited access* | Linking rules to MITRE ATT&CK techniques. Optional: without it, rules are imported without that link and the sync logs one warning. |

**Valhalla API key.** Get it from [valhalla.nextron-systems.com](https://valhalla.nextron-systems.com).

- The **demo key** is filled in by default. It gives you the free community feed.
- A **paid key** gives you the full Valhalla Sigma ruleset.

## 2. Set it up

1. In Sekoia, open **Configure → Integrations**, search for **Valhalla** and install **Nextron Valhalla Sigma Rules**.
2. Open **Configure → Playbooks**, click **+ New playbook**, choose your community and **Create a playbook from scratch**. Give it a name, for example *Sync Valhalla Sigma rules*.
3. As the trigger, select **Sync Valhalla Sigma rules into Sekoia Rules Catalog**.
4. Create an **account** for the trigger (see [Trigger account](#3-trigger-account)).
5. Create a **configuration** for the trigger (see [Trigger configuration](#4-trigger-configuration)). The defaults are a good start.
6. Save the playbook and turn it on. The first sync starts right away.

When the sync has finished, open **Configure → Rules Catalog** and filter by the tag `nextron-valhalla` to see the imported rules.

## 3. Trigger account

The account holds the connection details.

| Setting | What to enter |
|---|---|
| **Community UUID** | Leave empty unless your API key can access several communities (common for MSSPs). Then enter the community the rules should go to. To find the UUID: open the community in Sekoia, go to **Settings → General** and copy the part of the URL between `/communities/` and `/community-details`. |
| **Sekoia API key** | The key from step 1. |
| **Sekoia base URL** | The API URL of your Sekoia region. Default: `https://api.sekoia.io` (FRA1). For FRA2, MCO1 or UAE1, use `https://app.<region>.sekoia.io/api`, for example `https://app.fra2.sekoia.io/api`. |
| **Valhalla API key** | Your Valhalla key. Leave the default to use the demo key (community feed). |

Both API keys are hidden once you save the account.

## 4. Trigger configuration

The trigger configuration controls which rules are imported and how.

| Setting | Default | What it does |
|---|---|---|
| **Enabled** | `false` | Whether **newly imported** rules are enabled. Rules that are already in the catalog keep their current state. |
| **Frequency** | `86400` (daily) | Seconds between syncs. The minimum is `3600` (hourly). |
| **Disable removed** | `false` | Disables rules that Nextron removed from the feed, or that no longer meet your minimum level or status. See [Removed rules](#6-removed-rules). |
| **Minimum Sigma level** | `medium` | Imports rules with this level or higher: `informational` < `low` < `medium` < `high` < `critical`. Rules without a level are skipped. |
| **Minimum Sigma status** | `experimental` | Imports rules with this status or higher: `experimental` < `test` < `stable`. Rules marked `deprecated` or `unsupported`, or without a status, are never imported. |
| **Preserve rule names** | empty | Rules whose content syncs should never overwrite. One entry per line. See [Keeping your own changes](#7-keeping-your-own-changes). |

**About the status filter:** Nextron assigns Sigma statuses conservatively. Many rules stay `test` for a long time, even when they are in active use and don't cause noticeable false positives. Only a small part of the feed is `stable`. That's why the default imports all three statuses. Importing doesn't mean activating: with **Enabled** = `false`, a wider status range only gives you more rules to review.

You can change these settings at any time. The next sync uses the new values.

## 5. What a sync does

Every sync:

1. Downloads the current Sigma feed from Valhalla.
2. Keeps the rules that meet your minimum level and status.
3. Converts the rule fields to the field names Sekoia uses. Rules with fields that can't be converted are skipped, so you don't get rules that can never match.
4. **Creates** rules that aren't in your catalog yet, and **updates** the ones that are. Updates keep each rule's enabled or disabled state and the settings you made in Sekoia (see [Keeping your own changes](#7-keeping-your-own-changes)).
5. Re-enables rules that the integration disabled earlier and that are back in the feed.
6. Disables removed rules, if **Disable removed** is on.
7. Reports the results in a summary event (see [Checking the results](#8-checking-the-results)).

**The rule's log source doesn't limit where it runs.** A Sigma rule names a log source, for example `process_creation` on Windows. The imported rule keeps that block for information, but Sekoia's detection engine only evaluates the rule's detection logic. A converted rule can therefore also match other event types that contain the same fields. In other words, a successful conversion doesn't preserve the rule's original event scope. If a rule must only match one event type, that condition has to be part of its detection logic. See [Testing an imported rule](#9-testing-an-imported-rule).

Every imported rule is a normal Sekoia catalog rule and carries these tags:

| Tag | Meaning |
|---|---|
| `nextron-valhalla` | The rule comes from this integration. |
| `uuid-<valhalla_id>` | The rule's ID in Valhalla. The integration uses it to find the rule on later syncs. |
| `status-<status>` | The rule's Sigma status, for example `status-stable`. |
| `valhalla-auto-disabled` | Only on rules that **Disable removed** switched off. See [Removed rules](#6-removed-rules). |

If the API key has the optional intelligence permission, the rule is also linked to its MITRE ATT&CK techniques. The rule's sources are added to its description.

## 6. Removed rules

Nextron sometimes retires rules from the feed. A rule can also drop out of your selection when you raise the minimum level or status.

- With **Disable removed = false** (default), nothing changes in your catalog. The summary event only counts these rules under `to_disable`, so you can see what would happen.
- With **Disable removed = true**, those rules are **disabled** and get the tag `valhalla-auto-disabled`. They aren't deleted, and their settings stay as they are.

If a rule with that tag comes back, for example because you lower your minimums, the next sync updates it, **enables it again** and removes the tag. This works from any trigger configuration, including a new one. Rules you disabled yourself have no tag and always stay disabled. If you enable a tagged rule yourself, the tag is removed, so disabling it later stays your decision.

**Safeguards:** the integration doesn't disable any rules when:

- the feed is empty;
- the feed is more than 20% smaller than on the last sync. This could be a truncated download, or you switched to the demo key. If the smaller feed persists for 3 syncs in a row, it's accepted as the new normal;
- the sync was stopped before it finished.

The summary event gives the reason in `disable_skipped_reason`.

> **Use one sync trigger per community.** All triggers in a community work on the same imported rules. A trigger with **Disable removed** on disables every imported rule outside *its own* level and status filters, including rules that another trigger imported, and the other trigger enables them again on its next sync. If that happens, the summary event shows it under `reenable_conflicts` and the log has a warning. If you still run several triggers in one community, turn on **Disable removed** on only one of them, and set that trigger's filters to cover every rule you want to keep.

## 7. Keeping your own changes

Each sync updates an imported rule to the current Valhalla version. What happens to your changes depends on what you changed:

| Kept on every sync | Overwritten by every sync |
|---|---|
| Enabled or disabled state | Name |
| Entities and assets | Description |
| Parameters | Detection logic |
| Event fields | Severity |
| Similarity strategy | Tags |
| Validity | |
| Threats you linked | |
| Alert filters | |

So you can scope a rule to entities or assets, tune it with alert filters, or set its parameters without losing Valhalla updates.

To keep changes to the **content** (name, description, detection, severity, tags), add the rule to **Preserve rule names**:

- Put one entry per line.
- An entry matches the rule's **name** as shown in the Rules Catalog, or one of its **tags**.
- Several rules can share a name. To target exactly one rule, use its `uuid-<valhalla_id>` tag.
- Matching is case-sensitive.

Preserved rules no longer receive Valhalla updates. **Disable removed** still applies to them. To stop protecting a rule, delete its entry; the next sync updates it again.

## 8. Checking the results

After every sync the trigger sends a `valhalla-sigma-catalog-sync` event to the playbook. You can see it in the playbook's run history.

| Field | Meaning |
|---|---|
| `total_rules` | Number of rules in the Valhalla feed. |
| `created` / `updated` | Rules created or updated in this sync. |
| `preserved` | Rules not updated because they're on the preserve list. |
| `failed` | Rules that couldn't be created or updated. |
| `skipped_filter` | Rules below your minimum level or status. |
| `skipped_unmapped` | Rules skipped because a field couldn't be converted. |
| `top_unmapped` | The most common reasons for `skipped_unmapped`. |
| `stale` | Imported rules that keep their current version because the new version couldn't be converted. The log names up to five of them. |
| `re_enabled` / `reenable_failed` | Rules enabled again because they came back to the feed, or that couldn't be enabled. |
| `reenable_conflicts` | Rules that another trigger disabled again after this trigger re-enabled them (see [Removed rules](#6-removed-rules)). |
| `to_disable` | Rules that **Disable removed** would disable (or disabled, if it's on). |
| `newly_disabled` | Rules disabled in this sync. |
| `already_disabled` / `already_gone` | Rules that were already disabled, or that no longer exist in the catalog. |
| `disable_failed` | Rules that couldn't be disabled. |
| `disable_skipped_reason` | Empty, or why no rules were disabled: `empty_feed`, `feed_shrank` or `interrupted`. |
| `server_marker_count` | Imported rules found in the catalog. |
| `duplicate_markers` | Catalog rules with the same `uuid-*` tag. Delete the extra copies in the catalog. |
| `local_overridden` | Internal mapping entries the integration corrected from the catalog. Informational. |

## 9. Testing an imported rule

A successful sync shows that a rule was imported. It doesn't show that the rule detects what it should in your environment. Before you enable a rule, check it:

1. **Read the detection logic.** Open the imported rule in the Rules Catalog and look at its converted detection.
2. **Check your fields.** Make sure your normalized events contain the fields the rule uses.
3. **Test it against your data.** Use Sekoia's [pattern testing](https://docs.sekoia.io/xdr/features/detect/rules_catalog/#rule-testing) (**Test pattern**) to run the detection against 7, 30 or 60 days of your events, or test it against an event you know should match.
4. **Check the scope.** If the rule should only match one event type, also test it against a similar event of another type (see [What a sync does](#5-what-a-sync-does)).

No match in the history doesn't prove the rule is broken. The activity it looks for may simply not have happened in that time.

## 10. Working with the imported rules

- **Review before you enable.** New rules are imported disabled by default. Start with `high` and `critical` rules and enable more once you know the alert volume. You can restrict a rule to entities or assets; syncs keep these settings (see [Keeping your own changes](#7-keeping-your-own-changes)).
- **Enable the rules that fit your data.** A rule only works if your events contain the fields it uses. Check this before you enable it (see [Testing an imported rule](#9-testing-an-imported-rule)).
- **Tune with alert filters.** If a rule fires on legitimate activity, add an alert filter for that case rather than disabling the rule.
- **Disabling a rule is respected.** A rule you disable stays disabled on every later sync.
- **Removing the `nextron-valhalla` tag doesn't stop updates.** The integration still finds the rule and puts the tag back on the next sync. To stop updates, use **Preserve rule names** (see [Keeping your own changes](#7-keeping-your-own-changes)).
- **Duplicating a rule copies its tags.** The integration keeps updating the original and ignores the copy.

## 11. Common questions

**Can I run several triggers?**
Use one sync trigger per community. For several communities, set up one trigger for each, with the **Community UUID** set in its account. Several triggers in the same community affect each other (see [Removed rules](#6-removed-rules)). Also, if two triggers for the same community start their first run at the same moment, both find an empty catalog and both create the rules. If that happens, `duplicate_markers` shows it and you can delete the copies.

**I created a new playbook or trigger configuration. Will I get duplicates?**
No. The integration finds the rules it imported earlier through their tags and updates them.

**How do I remove all imported rules?**
Turn off the playbook, filter the Rules Catalog by the tag `nextron-valhalla` and delete the rules there.

**Why are some rules from the feed missing?**
There are three possible reasons:

- they're below your minimum level or status (`skipped_filter`);
- one of their fields couldn't be converted (`skipped_unmapped`);
- Sekoia rejected the request (`failed`). The first failure of each sync is logged with the error.

**What happens if the new version of an imported rule can't be converted?**
The version already in your catalog stays as it is. It isn't updated, and it isn't disabled. The sync counts it under `stale` and logs its name; the reason is listed in `top_unmapped`.

**Does the rule's `logsource` limit which events it runs on?**
No. Only the detection logic counts (see [What a sync does](#5-what-a-sync-does)).

**Does it import YARA rules?**
No. Only Valhalla's Sigma rules are imported.
