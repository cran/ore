numbers <- c("+44 20 1234 5678", "5678", "(020) 1234 5678")

expect_equal(ore_switch(numbers, "^\\+(\\d+) (\\d+) (\\d+ \\d+)$"="\\3", "^\\((\\d+)\\) (\\d+ \\d+)$"="\\2"), c("1234 5678", NA, "1234 5678"))
expect_equal(ore_switch(numbers, "^\\+(\\d+) (\\d+) (\\d+ \\d+)$"="\\3", "^\\((\\d+)\\) (\\d+ \\d+)$"="\\2", "None"), c("1234 5678", "None", "1234 5678"))
