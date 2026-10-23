# Daily nurse staffing model from the MSc thesis
# "Optimizing Nurse Staffing Schedules at MedyLife Healthcare Using Linear Programming" (GIMPA, 2023)
#
# For each day:  minimise R = x1 + x2 + x3 + x4 + x5
#   x1 >= a (morning), x2 >= b (afternoon), x3 >= c (night)
#   x4 <= d (day off), x5 <= e (leave)
#   x1 + x2 + x3 - x4 - x5 >= 0
#   x1 + x2 - x3 >= 0
#   all x integer and >= 0
#
# Run from the repository root:  Rscript R/thesis_model.R

library(lpSolve)

roster <- read.csv("data/medylife_roster_summary.csv")

solve_day <- function(a, b, c, d, e) {
  obj <- rep(1, 5)
  con <- rbind(
    c(1, 0, 0, 0, 0),
    c(0, 1, 0, 0, 0),
    c(0, 0, 1, 0, 0),
    c(0, 0, 0, 1, 0),
    c(0, 0, 0, 0, 1),
    c(1, 1, 1, -1, -1),
    c(1, 1, -1, 0, 0)
  )
  dir <- c(">=", ">=", ">=", "<=", "<=", ">=", ">=")
  rhs <- c(a, b, c, d, e, 0, 0)
  lp("min", obj, con, dir, rhs, all.int = TRUE)
}

results <- do.call(rbind, lapply(seq_len(nrow(roster)), function(i) {
  r <- roster[i, ]
  sol <- solve_day(r$morning, r$afternoon, r$night, r$day_off, r$leave)
  data.frame(day = r$day, morning = sol$solution[1], afternoon = sol$solution[2],
             night = sol$solution[3], day_off = sol$solution[4], leave = sol$solution[5],
             min_nurses = sol$objval, rostered = sum(r[, -1]), status = sol$status)
}))

stopifnot(all(results$status == 0))
results$status <- NULL
results$spare <- results$rostered - results$min_nurses
print(results, row.names = FALSE)
dir.create("results", showWarnings = FALSE)
write.csv(results, "results/thesis_daily_minimums.csv", row.names = FALSE)
