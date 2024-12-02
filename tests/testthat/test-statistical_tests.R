# This file is part of the NicksTTest package

library(testthat)
library(NicksTTest)

test_that("Package can be loaded", {
  expect_true("NicksTTest" %in% (.packages()))
})

test_that("Functions are available", {
  expect_true(exists("anova_ttest"))
  expect_true(exists("anova_tukey"))
  expect_true(exists("t_test_resilient"))
  expect_true(exists("t_test_resilient2"))
  expect_true(exists("geom_signif"))
})

test_that("Basic t-test works", {
  # Create sample data
  set.seed(123)
  test_data <- data.frame(
    value = c(rnorm(10, mean = 10), rnorm(10, mean = 12)),
    group = rep(c("A", "B"), each = 10)
  )
  
  # Test t_test_resilient
  result <- t_test_resilient(test_data, formula = value ~ group)
  expect_s3_class(result, "data.frame")
  expect_true("p" %in% names(result))
})

test_that("Basic ANOVA works", {
  # Create sample data
  set.seed(123)
  test_data <- data.frame(
    value = c(rnorm(10, mean = 10), rnorm(10, mean = 12), rnorm(10, mean = 14)),
    group = rep(c("A", "B", "C"), each = 10)
  )
  
  # Test anova_ttest
  result <- anova_ttest(test_data, "value", "group")
  expect_s3_class(result, "data.frame")
})
