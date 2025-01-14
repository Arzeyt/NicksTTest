#' Perform ANOVA with Optional T-Tests
#'
#' @param df A data frame containing the data
#' @param response The response variable name
#' @param treatment The treatment variable name
#' @param ... Additional grouping variables
#' @param do_ttest Logical; whether to perform t-tests if ANOVA is significant
#' @param clean Logical; whether to clean output by removing some columns
#' @param rstatix Logical; whether to use rstatix method for t-tests
#' @param adjust Character; p-value adjustment method
#'
#' @return A data frame containing ANOVA and optional t-test results
#' @export
#'
#' @importFrom rstatix t_test adjust_pvalue add_significance
#' @importFrom tidyverse %>%
#' @importFrom stats as.formula aov
anova_ttest <- function(df, response, treatment, ..., do_ttest = TRUE, clean = FALSE, rstatix = FALSE, adjust = "none") {
  library(rstatix)
  library(tidyverse)

  # Check reasonable variables
  if (rstatix == TRUE) {
    do_ttest <- TRUE
  }

  # First, take the ..., convert to quosure
  cells <- quos(...) # Capture the expression

  # Get selectors
  select1 <- lapply(cells, function(x) as_label(x)) %>%
    unlist() %>%
    c(response, treatment)

  # Create the ANOVA formula from the provided variables
  formula1 <- as.formula(paste(response, "~", treatment))

  # -----ANOVA----
  # ANOVA table generated by groups specified.
  anova_result <- df %>%
    select(select1) %>%
    group_by(...) %>%
    do({
      # For each df group, create an ANOVA table and return the result. Catch errors related to factors with less than 2 levels
      treatmentLevels <- unique(.[[treatment]]) %>% length()
      # print(paste("Treatment levels: ", treatmentLevels))

      if (treatmentLevels >= 2) {
        aov_res <- aov(formula1, data = .)
        aov_table <- aov_res %>%
          tidy() %>%
          mutate(
            anova_model = list(aov_res)
          )
      } else {
        print("Skipping a contrast because there's not enough treatment levels")
        data.frame(Note = "Not enough treatment levels")
      }
    })

  # Check to see if ANOVA table is empty. If so, print and exit
  if (nrow(anova_result) < 1) {
    return(print("No result"))
    # data.frame(Note="No result")
  }

  # If no group had enough treatment levels, the table will only contain two columns
  if (ncol(anova_result) < 3) {
    return(anova_result)
  }

  # Are any p-values under 0.05?
  significant_rows <- anova_result %>% filter(p.value < 0.05) %>% nrow()

  print(paste("Number of tests below 0.05: ", significant_rows))

  if (significant_rows < 1) {
    anova_result <- anova_result %>%
      mutate(
        Note = case_when(p.value > 0.05 ~ "p-value is above 0.05")
      )
    return(anova_result)
  }

  # ------------ T-Test----------

  # rstatix method of t_test for graphing purposes
  if (do_ttest && rstatix) {
    print("rstatix method")

    get_model <- function(anova_model) {
      anova_model$model
    }

    # Extract ANOVA model data
    anova_result <- anova_result %>%
      filter(p.value < 0.05) %>%
      mutate(
        anova_data = lapply(anova_model, get_model)
      ) %>%
      unnest(anova_data)

    print("Performing t-tests")

    # Filter out the factors that don't have enough levels
    anova_result <- anova_result %>%
      group_by(..., !!sym(treatment)) %>%
      mutate(
        rows = n()
      ) %>%
      ungroup() %>%
      group_by(...) %>%
      filter(rows > 1) %>%
      t_test(formula1, p.adjust.method = "none") %>%
      ungroup() %>%
      adjust_pvalue(method = adjust) %>%
      add_significance()

    return(anova_result)
  }

  # If we want to do t-test, and the ANOVA table worked
  if (do_ttest && "p.value" %in% colnames(anova_result)) {
    print("Doing Nick's T-test")

    nicks_t_test <- function(p.value, anova_model) {
      if (p.value < 0.05) {
        t_test(data = anova_model$model, formula = formula1)
      } else {
        data.frame(Note = "ANOVA p value is higher than 0.05")
      }
    }

    anova_result <- anova_result %>% rename(anova_p_value = p.value)

    ttest_result <- anova_result %>%
      filter(!is.na(anova_p_value)) %>% # Remove NA rows
      mutate(
        ttest = map2(anova_p_value, anova_model, nicks_t_test)
      ) %>%
      unnest(ttest, names_sep = "__", names_repair = "unique")

    # Make sure there's some t-tests done. If not, return ANOVA table
    if ("ttest__p" %in% colnames(ttest_result) == FALSE) {
      return(ttest_result)
    }

    # Adjust p-value
    n_comparisons <- ttest_result %>%
      filter(!is.na(ttest__p)) %>%
      nrow()

    ttest_result <- ttest_result %>%
      mutate(
        ttest__p.adj = ttest__p * n_comparisons,
        ttest__p.adj.signif = case_when(
          ttest__p.adj < 0.0001 ~ "****",
          ttest__p.adj < 0.001 ~ "***",
          ttest__p.adj < 0.01 ~ "**",
          ttest__p.adj < 0.05 ~ "*",
          TRUE ~ "ns"
        )
      )

    if (clean) {
      ttest_result <- ttest_result %>%
        select(-c("df", "sumsq", "meansq", "statistic"))
    } else {
      ttest_result
    }
  } else {
    anova_result
  }
}

#' Perform ANOVA with Optional Tukey Test
#'
#' @param df A data frame containing the data
#' @param response The response variable name
#' @param treatment The treatment variable name
#' @param ... Additional grouping variables
#' @param do_tukey Logical; whether to perform Tukey test if ANOVA is significant
#' @param clean Logical; whether to clean output by removing some columns
#' @param rstatix Logical; whether to use rstatix method
#'
#' @return A data frame containing ANOVA and optional Tukey test results
#' @export
#'
#' @importFrom dplyr filter mutate select rename group_by ungroup
#' @importFrom tidyr unnest
#' @importFrom rstatix tukey_hsd
anova_tukey <- function(df, response, treatment, ..., do_tukey = TRUE, clean = FALSE, rstatix = FALSE) {
  # First, take the ..., convert to quosure
  cells <- quos(...) # Capture the expressions

  # Then convert to a vector of string labels that we can add the response and treatment columns to
  select1 <- lapply(cells, function(x) as_label(x)) %>% unlist() %>% c(response, treatment)

  # Create the ANOVA formula from the provided variables
  formula1 <- as.formula(paste(response, "~", treatment))

  # Next, we want to do a do operation on each group provided.
  anova_result <- df %>%
    select(select1) %>%
    group_by(...) %>%
    do({
      # For each df group, create an ANOVA table and return the result. Catch errors related to factors with less than 2 levels
      treatmentLevels <- unique(.[[treatment]]) %>% length()
      print(paste("Treatment levels: ", treatmentLevels))

      if (treatmentLevels >= 2) {
        aov_res <- aov(formula1, data = .)
        aov_table <- aov_res %>%
          tidy() %>%
          mutate(
            anova_model = list(aov_res)
          )
      } else {
        print("Skipping a contrast because there's not enough treatment levels")
        data.frame(Note = "Not enough treatment levels")
      }
    })

  # If no group had enough treatment levels, the table will only contain two columns
  if (ncol(anova_result) == 2) {
    return(anova_table)
  }

  if (nrow(anova_result) < 1) {
    return(print("No result"))
  }

  if (!"p.value" %in% colnames(anova_result)) {
    return(anova_result)
  }

  count <- anova_result %>% filter(p.value < 0.05) %>% nrow()

  if (count < 1) {
    print("Nothing under 0.05 to run post-hoc tests on")
    return(anova_result)
  }

  # If rstatix = TRUE
  if (rstatix) {
    print("rstatix method")

    get_model <- function(anova_model) {
      anova_model$model
    }

    # Extract ANOVA model data
    anova_result <- anova_result %>%
      filter(p.value < 0.05) %>%
      mutate(
        anova_data = lapply(anova_model, get_model)
      ) %>%
      unnest(anova_data)

    print("Performing t-tests")

    # Filter out the factors that don't have enough levels and run Tukey
    anova_result <- anova_result %>%
      group_by(..., !!sym(treatment)) %>%
      mutate(
        rows = n()
      ) %>%
      ungroup() %>%
      group_by(...) %>%
      filter(rows > 1) %>%
      tukey_hsd(formula1)

    print(lapply(anova_result, levels))

    return(anova_result)
  }

  # TukeyHSD
  tukey_if_significant <- function(p_value, model) {
    if (is.na(p_value)) {
      NA
    } else if (any(is.na(model))) {
      NA
    } else if (p_value < 0.05) {
      tukey <- TukeyHSD(model) %>% tidy()
    } else {
      data.frame(Note = "ANOVA not significant")
    }
  }

  # If we want to do Tukey, and the ANOVA table worked
  if (do_tukey && "p.value" %in% colnames(anova_result)) {
    anova_result <- anova_result %>% rename(anova_p_value = p.value)

    tukey_result <- anova_result %>%
      filter(!is.na(anova_p_value)) %>%
      mutate(
        tukey = map2(anova_p_value, anova_model, tukey_if_significant)
      )

    # How many Tukey's tests were done (including failed)
    n_comparisons <- tukey_result %>%
      filter(!is.na(tukey)) %>%
      nrow()

    tukey_result <- tukey_result %>%
      unnest(tukey, names_sep = "_")

    if ("tukey_term" %in% colnames(tukey_result)) {
      # Tukey's tests minus failed
      n_comparisons <- n_comparisons - tukey_result %>% filter(is.na(tukey_term)) %>% nrow()

      tukey_result <- tukey_result %>%
        mutate(
          bonferroni_adj.p.value = n_comparisons * tukey_adj.p.value,
          sig = case_when(
            bonferroni_adj.p.value < 0.0001 ~ "****",
            bonferroni_adj.p.value < 0.001 ~ "***",
            bonferroni_adj.p.value < 0.01 ~ "**",
            bonferroni_adj.p.value < 0.05 ~ "*",
            TRUE ~ "ns"
          )
        )
    }

    if (clean) {
      tukey_result <- tukey_result %>% select(-c(sumsq, meansq, statistic, anova_model, tukey_conf.high, tukey_conf.low, tukey_null.value, tukey_estimate))
    } else {
      tukey_result
    }
  } else {
    anova_result
  }
}

#' Perform T-Test with Resilient Handling of Group Sizes
#'
#' @param df A data frame containing the data
#' @param formula A formula specifying the test
#' @param ... Additional grouping variables
#'
#' @return A data frame containing t-test results
#' @export
#'
#' @importFrom dplyr group_by add_count filter summarise left_join
#' @importFrom tidyr pivot_wider na.omit
#' @importFrom rstatix t_test
#' @importFrom stringr str_split_i str_remove
t_test_resilient <- function(df, formula, ...) {
  response <- formula %>% deparse() %>% str_split_i("~", 1) %>% str_remove(" ")
  treatment <- formula %>% deparse() %>% str_split_i("~", 2) %>% str_remove(" ")

  ttest <- df %>%
    group_by(..., !!sym(treatment)) %>%
    add_count() %>%
    filter(n > 2) %>%
    summarise(n = mean(n)) %>%
    pivot_wider(names_from = treatment, values_from = n) %>%
    na.omit() %>%
    left_join(df) %>%
    group_by(...) %>%
    t_test(formula)

  ttest
}

#' Perform T-Test with Enhanced Resilient Handling
#'
#' @param df A data frame containing the data
#' @param formula A formula specifying the test
#' @param ... Additional grouping variables
#'
#' @return A data frame containing t-test results
#' @export
#'
#' @importFrom dplyr group_by summarise filter semi_join across
#' @importFrom rstatix t_test
t_test_resilient2 <- function(df, formula, ...) {
  treatment <- formula %>% deparse() %>% str_split_i("~", 2) %>% str_trim()
  grouping_vars <- rlang::quos(...)

  grouping_var_names <- sapply(grouping_vars, rlang::as_name)

  counts <- df %>%
    group_by(!!!grouping_vars, !!sym(treatment)) %>%
    summarise(n = n(), .groups = "drop")

  counts_filtered <- counts %>%
    group_by(across(all_of(grouping_var_names))) %>%
    filter(n >= 2) %>%
    summarise(n_levels = n_distinct(!!sym(treatment)), .groups = "drop") %>%
    filter(n_levels == 2)

  df_filtered <- df %>%
    semi_join(counts_filtered, by = grouping_var_names)

  ttest <- df_filtered %>%
    group_by(across(all_of(grouping_var_names))) %>%
    t_test(formula)

  ttest
}

#' Create a Significance Layer for ggplot2
#'
#' @description A custom geom for adding significance indicators to ggplot2 plots
#'
#' @importFrom ggplot2 ggproto Geom aes draw_key_blank layer
#' @importFrom grid segmentsGrob textGrob gpar unit grobTree
#' @export
GeomSignif <- ggproto("GeomSignif", Geom,
  required_aes = c("xmin", "xmax", "y", "annotation"),
  default_aes = aes(
    colour = "black",
    linewidth = 0.5,
    linetype = "solid",
    alpha = 1,
    textsize = 3.88
  ),
  draw_key = draw_key_blank,

  setup_data = function(data, params) {
    if (!"y" %in% colnames(data) || any(is.na(data$y))) {
      stop("The 'y' column is missing or contains NA values.")
    }

    if (!is.numeric(data$xmin)) {
      data$xmin <- as.numeric(data$xmin)
    }
    if (!is.numeric(data$xmax)) {
      data$xmax <- as.numeric(data$xmax)
    }

    if (nrow(data) > 0) {
      data <- data %>%
        group_by(xmin, xmax) %>%
        arrange(y) %>%
        mutate(
          y = y + (row_number() - 1) * (params$step_increase %||% 0) + (params$y_offset %||% 0)
        ) %>%
        ungroup()
    }

    data
  },

  draw_panel = function(data, panel_params, coord, ...) {
    coords <- coord$transform(data, panel_params)

    lines <- segmentsGrob(
      x0 = unit(coords$xmin, "native"),
      x1 = unit(coords$xmax, "native"),
      y0 = unit(coords$y, "native"),
      y1 = unit(coords$y, "native"),
      gp = gpar(
        col = coords$colour,
        lwd = coords$linewidth * .pt,
        lty = coords$linetype,
        alpha = coords$alpha
      )
    )

    x_mid <- (coords$xmin + coords$xmax) / 2

    text <- textGrob(
      label = coords$annotation,
      x = unit(x_mid, "native"),
      y = unit(coords$y, "native") + unit(0.02, "npc"),
      just = "bottom",
      gp = gpar(
        col = coords$colour,
        fontsize = coords$textsize * .pt,
        alpha = coords$alpha
      )
    )

    grobTree(lines, text)
  }
)

#' Add Significance Annotations to ggplot2 Plots
#'
#' @param data Data frame containing significance test results
#' @param mapping Aesthetic mapping
#' @param stat The statistical transformation to use
#' @param position Position adjustment
#' @param na.rm Should NA values be removed?
#' @param show.legend Should the legend be shown?
#' @param inherit.aes Should the layer inherit aesthetics?
#' @param x_levels Levels of x variable
#' @param y_offset Vertical offset for annotations
#' @param step_increase Step increase for multiple annotations
#' @param ... Additional arguments passed to layer
#'
#' @return A ggplot2 layer
#' @export
#'
#' @importFrom ggplot2 layer aes
geom_signif <- function(data = NULL, mapping = NULL, stat = "identity",
                       position = "identity", na.rm = FALSE, show.legend = NA,
                       inherit.aes = FALSE, x_levels = NULL, y_offset = 0,
                       step_increase = 0, ...) {
  default_mapping <- aes(
    y = y.position,
    xmin = xmin,
    xmax = xmax,
    annotation = p.adj.signif
  )

  if (!is.null(mapping)) {
    user_mapping <- as.list(mapping)
    default_mapping <- modifyList(default_mapping, user_mapping)
  }

  layer(
    geom = GeomSignif,
    mapping = default_mapping,
    data = data,
    stat = stat,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list(
      na.rm = na.rm,
      y_offset = y_offset,
      step_increase = step_increase,
      ...
    )
  )
}
