# NicksTTest

An R package providing enhanced statistical testing functions with robust handling of edge cases and integrated visualization capabilities.

## Features

- `anova_ttest`: Performs ANOVA with automatic t-tests for significant results
- `anova_tukey`: Performs ANOVA with automatic Tukey's HSD test for significant results
- `t_test_resilient`: Performs t-tests with robust handling of group sizes
- `t_test_resilient2`: Enhanced version of t_test_resilient with improved group handling
- `geom_signif`: Custom ggplot2 geom for adding significance indicators to plots

## Installation

You can install the package directly from GitHub:

```R
# install.packages("devtools")
devtools::install_github("YourGitHubUsername/NicksTTest")
```

## Usage

```R
library(NicksTTest)

# Example of ANOVA with t-tests
result <- anova_ttest(data, "response_var", "treatment_var", grouping_var)

# Example of resilient t-test
result <- t_test_resilient(data, response ~ treatment, grouping_var)

# Example of adding significance indicators to a ggplot
library(ggplot2)
ggplot(data, aes(x = group, y = value)) +
  geom_boxplot() +
  geom_signif(data = test_results)
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
