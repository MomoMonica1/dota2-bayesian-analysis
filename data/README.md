# Research inputs

The original presentation identifies the source only as a **Kaggle Dota 2 dataset**. The exact dataset URL/version and original CSVs were not supplied. No download link is guessed, and no raw data is redistributed here.

Place these files in this directory, or supply `--data-dir /path/to/csvs`:

| File | Required columns | Meaning |
| --- | --- | --- |
| `players.csv` | `match_id`, `account_id`, `player_slot`, `kills`, `deaths`, `assists`, `gold` | One player-slot record per match |
| `match.csv` | `match_id`, `game_mode`, `radiant_win`, `duration` | One record per match; duration in seconds |
| `teamfights_players.csv` | `match_id`, `player_slot`, `damage`, `xp_end` | Zero or more teamfight records per player-slot and match |

`match_id` and `account_id` are read as character identifiers. `account_id = 0` denotes anonymous players. Player slots must be `0–4` for Radiant or `128–132` for Dire. `radiant_win` accepts `0/1` or `FALSE/TRUE`. Other listed fields are numeric; extra columns are ignored.

The notebook also read `player_ratings.csv`, but it contributed no predictor to the models. It is not required by this implementation. Unused tower-damage, hero-damage, and healing fields likewise are not required.

## Selection and missingness

1. Keep matches with `game_mode == 2` and identifiable players.
2. Derive each player's outcome using the team bit (mask 128) and `radiant_win`.
3. Count wins and games once per unique account. Accounts with fewer than three observed games are retained in the prepared table but excluded from beta-binomial fitting.
4. Sum teamfight damage and `xp_end` over records. Absent event rows and missing event metrics contribute zero, following the original convention. This is an assumption about missingness, not proof that no teamfight occurred. Summed `xp_end` is an aggregate of recorded end values, not necessarily XP gained.
5. Drop player-regression rows with missing required predictors. These omissions do not change previously computed player win counts.
6. Keep a team-level match only when **all ten slots remain after anonymous-player and missing-feature exclusions**. Compute Radiant minus Dire explicitly. This restricts the team analysis to complete, identifiable matches.

Duplicate `(match_id, player_slot)` keys, duplicate identifiable `(match_id, account_id)` keys, duplicate match IDs, missing keys, invalid slots, and malformed values fail with an error. Repeated teamfight keys are expected and are aggregated. Matches without corresponding input records are removed by the explicit join.

Raw CSVs and generated prepared records are ignored by Git. Obtain and use the source data under its original terms; matching this schema alone does not establish that a replacement dataset is the historical one.
