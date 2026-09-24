# Prepare observed player records and complete Radiant–Dire match pairs.
# No network calls: input CSVs must be supplied separately.

read_input <- function(data_dir, filename, columns) {
  path <- file.path(data_dir, filename)
  if (!file.exists(path)) stop("Missing input: ", path, call. = FALSE)
  x <- utils::read.csv(path, colClasses = "character", check.names = FALSE)
  missing <- setdiff(columns, names(x))
  if (length(missing)) stop(filename, " missing columns: ",
                            paste(missing, collapse = ", "), call. = FALSE)
  x[, columns, drop = FALSE]
}

numeric_columns <- function(x, columns, filename) {
  for (column in columns) {
    original <- x[[column]]
    value <- suppressWarnings(as.numeric(original))
    invalid <- !is.na(original) & nzchar(trimws(original)) & is.na(value)
    if (any(invalid) || any(is.infinite(value))) {
      stop(filename, ": invalid numeric value in ", column, call. = FALSE)
    }
    x[[column]] <- value
  }
  x
}

assert_unique <- function(x, columns, label) {
  if (anyDuplicated(x[, columns, drop = FALSE])) {
    stop(label, " must be unique by ", paste(columns, collapse = ", "), call. = FALSE)
  }
}

assert_keys <- function(x, columns, label) {
  if (any(vapply(x[, columns, drop = FALSE], function(z) {
    any(is.na(z) | !nzchar(trimws(as.character(z))))
  }, logical(1)))) stop(label, " has missing keys", call. = FALSE)
}

prepare_data <- function(data_dir = "data") {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Install dplyr first: Rscript scripts/install_dependencies.R", call. = FALSE)
  }
  player_columns <- c("match_id", "account_id", "player_slot", "kills", "deaths",
                      "assists", "gold")
  players <- read_input(data_dir, "players.csv", player_columns)
  matches <- read_input(data_dir, "match.csv", c("match_id", "game_mode", "radiant_win", "duration"))
  fights <- read_input(data_dir, "teamfights_players.csv", c("match_id", "player_slot", "damage", "xp_end"))
  players <- numeric_columns(players, c("player_slot", "kills", "deaths", "assists", "gold"), "players.csv")
  matches <- numeric_columns(matches, c("game_mode", "duration"), "match.csv")
  fights <- numeric_columns(fights, c("player_slot", "damage", "xp_end"), "teamfights_players.csv")
  assert_keys(players, c("match_id", "account_id", "player_slot"), "players.csv")
  assert_keys(matches, "match_id", "match.csv")
  assert_keys(fights, c("match_id", "player_slot"), "teamfights_players.csv")
  assert_unique(players, c("match_id", "player_slot"), "players.csv")
  assert_unique(players[players$account_id != "0", , drop = FALSE],
                c("match_id", "account_id"), "Non-anonymous players")
  assert_unique(matches, "match_id", "match.csv")
  valid_slots <- c(0:4, 128:132)
  if (any(!players$player_slot %in% valid_slots) || any(!fights$player_slot %in% valid_slots)) {
    stop("player_slot must be one of 0:4 or 128:132", call. = FALSE)
  }
  flag <- tolower(trimws(matches$radiant_win))
  if (any(is.na(flag) | !flag %in% c("0", "1", "false", "true"))) {
    stop("radiant_win must be 0/1 or TRUE/FALSE", call. = FALSE)
  }
  matches$radiant_win <- as.integer(flag %in% c("1", "true"))
  selected_matches <- matches[!is.na(matches$game_mode) & matches$game_mode == 2, , drop = FALSE]

  # Multiple teamfight events per slot are expected; absent events and NA event
  # metrics contribute zero, matching the supplied analysis's convention.
  fight_totals <- dplyr::summarise(
    dplyr::group_by(fights, match_id, player_slot),
    teamfight_damage = sum(damage, na.rm = TRUE),
    teamfight_xp_end = sum(xp_end, na.rm = TRUE), .groups = "drop")
  joined <- dplyr::inner_join(players[players$account_id != "0", , drop = FALSE],
                              selected_matches, by = "match_id")
  # Bit 7 (mask 128), applied to every row: 0 = Radiant, 1 = Dire.
  joined$radiant <- bitwAnd(as.integer(joined$player_slot), 128L) == 0L
  joined$win <- as.integer(joined$radiant == as.logical(joined$radiant_win))
  counts <- dplyr::summarise(dplyr::group_by(joined, account_id),
                             num_win = sum(win), num_game = dplyr::n(),
                             win_prob = mean(win), .groups = "drop")
  counts$cohort <- ifelse(counts$num_game < 3, "below_minimum",
                         ifelse(counts$num_game <= 10, "3_to_10", "over_10"))
  joined <- dplyr::left_join(joined, fight_totals, by = c("match_id", "player_slot"))
  for (column in c("teamfight_damage", "teamfight_xp_end")) {
    joined[[column]][is.na(joined[[column]])] <- 0
  }
  features <- c("kills", "deaths", "assists", "gold", "teamfight_damage",
                "teamfight_xp_end", "duration")
  complete_rows <- stats::complete.cases(joined[, features, drop = FALSE])
  player_matches <- joined[complete_rows, , drop = FALSE]

  # Avoid partial-team totals after exclusions. A valid match has both full
  # teams; slot validation and uniqueness above make this exactly five a side.
  sizes <- dplyr::summarise(dplyr::group_by(player_matches, match_id),
                            n_players = dplyr::n(), .groups = "drop")
  complete_ids <- sizes$match_id[sizes$n_players == 10]
  team_players <- player_matches[player_matches$match_id %in% complete_ids, , drop = FALSE]
  teams <- dplyr::summarise(dplyr::group_by(team_players, match_id, radiant),
                            kills = sum(kills), gold = sum(gold),
                            teamfight_damage = sum(teamfight_damage),
                            teamfight_xp = sum(teamfight_xp_end),
                            duration = dplyr::first(duration),
                            radiant_win = dplyr::first(radiant_win), .groups = "drop")
  paired <- dplyr::inner_join(teams[teams$radiant, , drop = FALSE],
                              teams[!teams$radiant, , drop = FALSE],
                              by = "match_id", suffix = c("_radiant", "_dire"))
  team_matches <- data.frame(match_id = paired$match_id,
                            diff_kills = paired$kills_radiant - paired$kills_dire,
                            diff_gold = paired$gold_radiant - paired$gold_dire,
                            diff_teamfight_damage = paired$teamfight_damage_radiant - paired$teamfight_damage_dire,
                            diff_teamfight_xp = paired$teamfight_xp_radiant - paired$teamfight_xp_dire,
                            duration = paired$duration_radiant,
                            win = as.integer(paired$radiant_win_radiant))
  audit <- data.frame(stage = c("input_player_rows", "mode_2_matches", "eligible_player_rows",
                                "unique_eligible_players", "player_rows_with_complete_features", "complete_team_matches"),
                      n = c(nrow(players), nrow(selected_matches), nrow(joined),
                            nrow(counts), nrow(player_matches), nrow(team_matches)))
  list(player_matches = player_matches, player_counts = counts,
       team_matches = team_matches, audit = audit)
}

make_logistic_data <- function(x, features, coefficient_scale, intercept_scale) {
  if (nrow(x) < 2) stop("Need at least two complete observations for logistic regression", call. = FALSE)
  center <- vapply(x[, features, drop = FALSE], mean, numeric(1))
  spread <- vapply(x[, features, drop = FALSE], stats::sd, numeric(1))
  if (any(!is.finite(spread) | spread == 0)) {
    stop("Constant or invalid predictors: ", paste(features[!is.finite(spread) | spread == 0], collapse = ", "), call. = FALSE)
  }
  X <- sweep(sweep(as.matrix(x[, features, drop = FALSE]), 2, center, "-"), 2, spread, "/")
  list(stan = list(N = nrow(X), K = ncol(X), X = X, y = as.integer(x$win),
                   coefficient_scale = coefficient_scale, intercept_scale = intercept_scale),
       scaling = data.frame(feature = features, mean = center, sd = spread, row.names = NULL))
}

make_binomial_data <- function(counts, cohort, omega_a, omega_b, kappa_shape, kappa_rate) {
  x <- counts[counts$cohort == cohort, , drop = FALSE]
  if (!nrow(x)) stop("No eligible players in cohort: ", cohort, call. = FALSE)
  list(N = nrow(x), y = as.integer(x$num_win), n = as.integer(x$num_game),
       omega_a = omega_a, omega_b = omega_b,
       kappa_shape = kappa_shape, kappa_rate = kappa_rate)
}
