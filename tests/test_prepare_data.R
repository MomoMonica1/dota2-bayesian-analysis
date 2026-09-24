# Synthetic regression tests. These are invented data, not observed Dota 2 results.
# Run from any directory: Rscript tests/test_prepare_data.R
args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args, value = TRUE)
if (!length(script_arg)) stop("Run this file using Rscript.")
script_path <- normalizePath(sub("^--file=", "", script_arg[[1]]))
repo_dir <- dirname(dirname(script_path))
source(file.path(repo_dir, "R", "prepare_data.R"))

checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL: ", label, call. = FALSE)
  checks <<- checks + 1L
  cat("PASS: ", label, "\n", sep = "")
}
equal <- function(actual, expected, label) {
  check(isTRUE(all.equal(unname(actual), unname(expected), check.attributes = FALSE)), label)
}
expect_error <- function(expr, label, pattern = NULL) {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(err, "error"), label)
  if (!is.null(pattern)) check(grepl(pattern, conditionMessage(err), ignore.case = TRUE),
                               paste(label, "has an actionable message"))
}

# Eleven Captains Mode matches plus one other-mode match. Every match has
# precisely five Radiant slots (0:4) and five Dire slots (128:132).
fixture <- function() {
  slots <- c(0:4, 128:132)
  players <- do.call(rbind, lapply(seq_len(12), function(m) {
    accounts <- c(if (m <= 3) 101 else 102, 201,
                  if (m <= 2) 301 else 302, 401, 501, 601:605)
    data.frame(match_id = m, account_id = accounts, player_slot = slots,
               kills = c(2, 4, 6, 8, 10, 1, 3, 5, 7, 9),
               deaths = 1:10, assists = 11:20,
               gold = c(100, 200, 300, 400, 500, 10, 20, 30, 40, 50),
               tower_damage = 21:30, hero_damage = 31:40, hero_healing = 41:50)
  }))
  matches <- data.frame(match_id = 1:12, game_mode = c(rep(2, 11), 1),
                        radiant_win = rep(c(TRUE, FALSE), 6),
                        duration = 1800 + (1:12) * 60)
  events <- do.call(rbind, lapply(seq_len(12), function(m) {
    data.frame(match_id = m, player_slot = rep(slots, 2),
               damage = c((1:10) * 10, 1:10),
               xp_end = c((1:10) * 100, (1:10) * 2))
  }))
  list(players = players, match = matches, teamfights_players = events)
}
with_fixture <- function(input, callback) {
  path <- tempfile("dota2-synthetic-")
  dir.create(path)
  on.exit(unlink(path, recursive = TRUE), add = TRUE)
  for (name in names(input)) {
    write.csv(input[[name]], file.path(path, paste0(name, ".csv")), row.names = FALSE)
  }
  callback(path)
}
prepare_fixture <- function(input) with_fixture(input, prepare_data)

input <- fixture()
out <- prepare_fixture(input)
pm <- out$player_matches
pc <- out$player_counts
tm <- out$team_matches

equal(nrow(pm), 110, "Only the 11 Captains Mode matches enter player data")
check(!12 %in% pm$match_id, "Other game modes are excluded before win counts")
check(all(pm$radiant[pm$player_slot %in% 0:4]), "All five low slots are Radiant")
check(all(!pm$radiant[pm$player_slot %in% 128:132]), "All five high slots are Dire")
equal(pm$win[pm$match_id == 1 & pm$player_slot %in% 0:4], rep(1, 5),
      "Every Radiant player wins a Radiant-winning match")
equal(pm$win[pm$match_id == 1 & pm$player_slot %in% 128:132], rep(0, 5),
      "Every Dire player loses a Radiant-winning match")
equal(pm$win[pm$match_id == 2 & pm$player_slot %in% 128:132], rep(1, 5),
      "Every Dire player wins a Dire-winning match")
check(!anyDuplicated(pc$account_id), "Binomial input has one row per account")
equal(pc$num_game[pc$account_id == 101], 3, "Three-game cohort boundary counts matches once")
equal(pc$num_win[pc$account_id == 101], 2, "Three-game account has two actual wins")
equal(pc$win_prob[pc$account_id == 101], 2 / 3, "Win probability agrees with unique binomial counts")
equal(pc$num_game[pc$account_id == 102], 8, "Second account in the same slot has eight games")
equal(pc$num_win[pc$account_id == 102], 4, "Second account in the same slot has four wins")
equal(pc$num_game[pc$account_id == 201], 11, "Experienced account has eleven games")
equal(pc$num_win[pc$account_id == 201], 6, "Experienced Radiant account has six wins")
equal(pc$num_win[pc$account_id == 601], 5, "Experienced Dire account has five wins")
equal(pc$cohort[pc$account_id == 301], "below_minimum", "Two-game account stays below the modeled cohorts")
equal(pc$cohort[pc$account_id == 101], "3_to_10", "Three-game account enters the 3–10 cohort")
equal(pc$cohort[pc$account_id == 201], "over_10", "Eleven-game account enters the experienced cohort")
binomial <- make_binomial_data(pc, "3_to_10", 1, 1, 0.1, 0.1)
equal(binomial$N, 3, "Stan binomial N is the count of accounts, not repeated match rows")
equal(sort(binomial$n), c(3L, 8L, 9L), "Stan binomial trials preserve each account's unique matches")
equal(sort(binomial$y), c(2L, 4L, 5L), "Stan binomial outcomes preserve each account's unique wins")

equal(nrow(tm), 11, "Exactly one paired 5v5 team observation per complete match")
check(!anyDuplicated(tm$match_id), "Team observations have unique match IDs")
equal(tm$diff_kills, rep(5, 11), "Team kills are Radiant total minus Dire total")
equal(tm$diff_gold, rep(1350, 11), "Team gold uses five players on each side")
equal(tm$diff_teamfight_damage, rep(-275, 11), "All teamfight events aggregate before team subtraction")
equal(tm$diff_teamfight_xp, rep(-2550, 11), "Teamfight XP differences retain the correct direction")
equal(tm$win[order(tm$match_id)], as.integer(input$match$radiant_win[1:11]),
      "Team response is the Radiant match outcome")

# Row ordering must not influence a team's side or the differential sign.
reordered <- input
reordered$players <- reordered$players[nrow(reordered$players):1, ]
reordered$match <- reordered$match[nrow(reordered$match):1, ]
reordered$teamfights_players <- reordered$teamfights_players[nrow(reordered$teamfights_players):1, ]
shuffled <- prepare_fixture(reordered)$team_matches
cols <- c("match_id", "diff_kills", "diff_gold", "diff_teamfight_damage", "diff_teamfight_xp", "win")
equal(as.data.frame(shuffled[order(shuffled$match_id), cols]),
      as.data.frame(tm[order(tm$match_id), cols]), "Team pairing is independent of input row order")

anonymous <- input
anonymous$players$account_id[anonymous$players$match_id == 1 & anonymous$players$player_slot == 0] <- 0
anon_out <- prepare_fixture(anonymous)
check(!0 %in% anon_out$player_counts$account_id && !0 %in% anon_out$player_matches$account_id,
      "Anonymous account zero is excluded from player analyses")
equal(nrow(anon_out$player_matches), 109, "Anonymous exclusion drops exactly one player observation")
check(!1 %in% anon_out$team_matches$match_id && nrow(anon_out$team_matches) == 10,
      "Anonymous exclusion prevents an incomplete 4v5 team comparison")

incomplete <- input
incomplete$players <- incomplete$players[!(incomplete$players$match_id == 2 &
                                           incomplete$players$player_slot == 132), ]
incomplete_out <- prepare_fixture(incomplete)
check(!2 %in% incomplete_out$team_matches$match_id && nrow(incomplete_out$team_matches) == 10,
      "A missing fifth player excludes both sides of that match")
equal(nrow(incomplete_out$player_matches), 109, "Other valid individual observations remain eligible")
equal(incomplete_out$player_counts$cohort[incomplete_out$player_counts$account_id == 605],
      "3_to_10", "Ten-game account remains in the 3–10 cohort")

missing_metric <- input
missing_metric$players$kills[missing_metric$players$match_id == 3 &
                               missing_metric$players$player_slot == 0] <- NA
metric_out <- prepare_fixture(missing_metric)
equal(metric_out$player_counts$num_game[metric_out$player_counts$account_id == 101], 3,
      "Binomial counts do not depend on complete regression features")
check(!3 %in% metric_out$team_matches$match_id && nrow(metric_out$team_matches) == 10,
      "Missing regression feature excludes an incomplete team pair")

no_event <- input
no_event$teamfights_players <- no_event$teamfights_players[
  !(no_event$teamfights_players$match_id == 1 & no_event$teamfights_players$player_slot == 0), ]
event_out <- prepare_fixture(no_event)
equal(event_out$player_matches$teamfight_damage[event_out$player_matches$match_id == 1 &
                                                event_out$player_matches$player_slot == 0], 0,
      "No teamfight event gives zero aggregated damage")
equal(event_out$team_matches$diff_teamfight_damage[event_out$team_matches$match_id == 1], -286,
      "Missing event changes only its player's contribution")

duplicate <- input
duplicate$players <- rbind(duplicate$players, duplicate$players[1, ])
expect_error(prepare_fixture(duplicate), "Duplicate player slots are rejected instead of double counted")
duplicate <- input
duplicate$players$account_id[2] <- duplicate$players$account_id[1]
expect_error(prepare_fixture(duplicate), "Duplicate account within one match is rejected")
duplicate <- input
duplicate$match <- rbind(duplicate$match, duplicate$match[1, ])
expect_error(prepare_fixture(duplicate), "Duplicate match rows cannot multiply joined observations")
invalid_slot <- input
invalid_slot$players$player_slot[1] <- 5
expect_error(prepare_fixture(invalid_slot), "A low slot outside 0:4 is rejected", "player_slot")
invalid_slot <- input
invalid_slot$teamfights_players$player_slot[1] <- 133
expect_error(prepare_fixture(invalid_slot), "An invalid teamfight player slot is rejected", "player_slot")

# Verify standardization and response structure with independent hand-checkable
# synthetic values. These are not estimates from the original project.
model_fixture <- data.frame(a = c(1, 2, 3), b = c(2, 4, 6), win = c(0, 1, 1))
model <- make_logistic_data(model_fixture, c("a", "b"), 0.5, 1)
equal(model$stan$X, cbind(c(-1, 0, 1), c(-1, 0, 1)),
      "Logistic design matrix uses sample standard deviation")
equal(model$stan$y, c(0L, 1L, 1L), "Logistic response preserves binary outcomes")
equal(model$scaling$mean, c(2, 4), "Scaling metadata stores predictor means")
equal(model$scaling$sd, c(1, 2), "Scaling metadata stores predictor scales")
model_fixture$b <- 1
expect_error(make_logistic_data(model_fixture, c("a", "b"), 0.5, 1),
             "Constant predictors fail before model fitting", "b")

for (missing in names(input)) {
  missing_input <- input
  missing_input[[missing]] <- NULL
  expect_error(prepare_fixture(missing_input), paste("Missing", paste0(missing, ".csv"), "fails clearly"),
               paste0(missing, "\\.csv"))
}
for (table in names(input)) {
  missing_column <- input
  missing_column[[table]]$match_id <- NULL
  expect_error(prepare_fixture(missing_column), paste("Missing match_id in", table, "fails clearly"),
               "match_id")
}
cat("\n", checks, " synthetic data-preparation checks passed.\n", sep = "")
cat("No real dataset or MCMC model fitting was used.\n")
