# Extension of the thesis model: how many nurses does the ward need on its books?
#
# The thesis model finds the minimum number of nurses on duty each day. It does not
# say who works which days, so it sets day-off and leave to zero. This model builds a
# weekly roster where every nurse gets consecutive days off, then counts the head count.
#
# Assumptions (change them below):
#   * each nurse works one shift type for the week (morning, afternoon or night)
#   * day-shift nurses (6-hour shifts) work 5 consecutive days, then 2 days off
#   * night nurses (12-hour shifts) work 4 consecutive nights, then 3 nights off
#   * a relief allowance covers annual leave and sickness
#
# Integer programme for each shift s:
#   y_k = nurses whose working block starts on day k (k = Mon..Sun)
#   minimise   sum_k y_k
#   subject to sum of y_k over patterns working on day j  >=  requirement_sj   for every day j
#
# Run from the repository root:  Rscript R/weekly_roster_model.R

library(lpSolve)

roster <- read.csv("data/medylife_roster_summary.csv")
days <- roster$day
WORK_DAYS <- c(morning = 5, afternoon = 5, night = 4)
RELIEF <- 0.12  # extra head count for leave and sickness (12% is a common planning figure)

# 7 x 7 matrix: entry [j, k] = 1 if the pattern starting on day k works on day j
pattern_matrix <- function(work) {
  sapply(0:6, function(k) as.integer(((0:6 - k) %% 7) < work))
}

solve_shift <- function(req, work) {
  A <- pattern_matrix(work)
  sol <- lp("min", rep(1, 7), A, rep(">=", 7), req, all.int = TRUE)
  stopifnot(sol$status == 0)
  list(starts = setNames(sol$solution, days), on_duty = as.vector(A %*% sol$solution),
       nurses = sol$objval)
}

out <- lapply(names(WORK_DAYS), function(s) solve_shift(roster[[s]], WORK_DAYS[[s]]))
names(out) <- names(WORK_DAYS)

cat("Nurses starting their working block on each day:\n")
print(t(sapply(out, `[[`, "starts")))

cover <- data.frame(day = days,
                    required = roster$morning + roster$afternoon + roster$night,
                    scheduled = Reduce(`+`, lapply(out, `[[`, "on_duty")))
cover$surplus <- cover$scheduled - cover$required
cat("\nDaily cover (all shifts):\n")
print(cover, row.names = FALSE)

core <- sum(sapply(out, `[[`, "nurses"))
with_relief <- ceiling(core * (1 + RELIEF))
current <- round(mean(rowSums(roster[, -1])))
summary <- data.frame(
  measure = c(paste0("Nurses needed: morning (", WORK_DAYS[["morning"]], " days/week)"),
              paste0("Nurses needed: afternoon (", WORK_DAYS[["afternoon"]], " days/week)"),
              paste0("Nurses needed: night (", WORK_DAYS[["night"]], " nights/week)"),
              "Core roster", paste0("With ", RELIEF * 100, "% relief for leave and sickness"),
              "Current roster (average head count in the data)"),
  nurses = c(out$morning$nurses, out$afternoon$nurses, out$night$nurses, core, with_relief, current))
cat("\n"); print(summary, row.names = FALSE)

write.csv(cover, "results/weekly_cover.csv", row.names = FALSE)
write.csv(summary, "results/weekly_roster_summary.csv", row.names = FALSE)

png("results/weekly_cover.png", width = 1100, height = 520, res = 130)
par(mar = c(4, 4.5, 3, 1))
m <- rbind(cover$required, cover$scheduled)
bp <- barplot(m, beside = TRUE, names.arg = substr(days, 1, 3), col = c("#cde2fb", "#2a78d6"),
              border = NA, ylim = c(0, max(m) * 1.2), ylab = "Nurses on duty",
              main = "Required vs scheduled nurses on duty (5-on/2-off days, 4-on/3-off nights)")
text(bp[2, ], m[2, ] + 2, m[2, ], cex = .8)
legend("topright", c("Required (thesis minimum)", "Scheduled by weekly roster"),
       fill = c("#cde2fb", "#2a78d6"), border = NA, bty = "n", cex = .85)
invisible(dev.off())

# ---- sensitivity: how much does the answer depend on the rostering rules? ----
total_req <- roster$morning + roster$afternoon + roster$night
scenarios <- list(
  list(name = "Fixed shift type; 5 days, nights 4 (base case)", fixed = TRUE, w = c(5, 5, 4)),
  list(name = "Fixed shift type; 5 days for every shift", fixed = TRUE, w = c(5, 5, 5)),
  list(name = "Fixed shift type; 6 days, nights 4", fixed = TRUE, w = c(6, 6, 4)),
  list(name = "Any nurse can work any shift; 5 days a week", fixed = FALSE, w = 5),
  list(name = "Any nurse can work any shift; 6 days a week", fixed = FALSE, w = 6)
)
sens <- do.call(rbind, lapply(scenarios, function(sc) {
  n <- if (sc$fixed) {
    sum(mapply(function(s, w) solve_shift(roster[[s]], w)$nurses, names(WORK_DAYS), sc$w))
  } else {
    solve_shift(total_req, sc$w)$nurses
  }
  data.frame(scenario = sc$name, core_nurses = n, with_relief = ceiling(n * (1 + RELIEF)))
}))
cat("\nSensitivity to rostering rules:\n")
print(sens, row.names = FALSE)
write.csv(sens, "results/sensitivity.csv", row.names = FALSE)

days_off <- sum(roster$day_off) / current
cat(sprintf("\nIn the current data, %d nurses share %d days off a week: %.1f days off per nurse.\n",
            current, sum(roster$day_off), days_off))

png("results/headcount_scenarios.png", width = 1100, height = 560, res = 130)
par(mar = c(4.5, 13.5, 3, 2))
lab <- c("Fixed shift, 5 days (nights 4)", "Fixed shift, 5 days", "Fixed shift, 6 days (nights 4)",
         "Any shift, 5 days a week", "Any shift, 6 days a week")
bp <- barplot(rev(sens$core_nurses), horiz = TRUE, names.arg = rev(lab), las = 1, col = "#2a78d6",
              border = NA, xlim = c(0, 100), xlab = "Nurses needed on the roster (before relief)",
              main = "Nurses needed under each days-off rule")
text(rev(sens$core_nurses) + 3, bp, rev(sens$core_nurses), cex = .85)
abline(v = current, col = "#d03b3b", lwd = 2, lty = 2)
text(current, max(bp) + .9, paste0("Current roster: ", current), col = "#d03b3b", cex = .85, xpd = TRUE)
invisible(dev.off())
