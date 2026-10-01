# ============================================================
# Project 18.2
# Historical Market Price Ingestion & Incremental Data Pipeline
# ============================================================


# ============================================================
# 0. Setup
# ============================================================

library(DBI)
library(odbc)
library(dplyr)
library(tidyquant)
library(quantmod)


# ============================================================
# 1. Configuration
# ============================================================

# TRUE  = write data to SQL Server
# FALSE = dry run only
WRITE_TO_SQL <- TRUE

# AUTO       = tq_get() first, getSymbols() fallback
# TQ_GET     = use tq_get() only
# GETSYMBOLS = use getSymbols() only
# COMPARE    = download with both methods and compare
DOWNLOAD_STRATEGY <- "AUTO"

# Calendar days to re-fetch for incremental loads
OVERLAP_DAYS <- 5

# Initial historical download date
INITIAL_FROM_DATE <- as.Date("1900-01-01")


# ============================================================
# 2. Console Message Helpers
# ============================================================

print_header <- function(title) {

  cat("\n")
  cat("========================================\n")
  cat(title, "\n")
  cat("========================================\n")
}


print_section <- function(title) {

  cat("\n")
  cat("----------------------------------------\n")
  cat(title, "\n")
  cat("----------------------------------------\n")
}


print_info <- function(message) {

  cat("[INFO] ", message, "\n", sep = "")
}


print_success <- function(message) {

  cat("[SUCCESS] ", message, "\n", sep = "")
}


print_warning <- function(message) {

  cat("[WARNING] ", message, "\n", sep = "")
}


print_error <- function(message) {

  cat("[ERROR] ", message, "\n", sep = "")
}


format_date <- function(x) {

  if (length(x) == 0) {

    return("NONE")
  }


  value <- x[[1]]


  if (is.null(value) || is.na(value)) {

    return("NONE")
  }


  format(
    as.Date(value),
    "%Y-%m-%d"
  )
}


# ============================================================
# 3. Database Connection
# ============================================================

connect_db <- function() {

  password <- Sys.getenv(
    "MSSQL_SA_PASSWORD"
  )


  if (identical(password, "")) {

    stop(
      paste(
        "MSSQL_SA_PASSWORD is not set.",
        "Set the environment variable before connecting to SQL Server."
      )
    )
  }


  con <- dbConnect(
    odbc(),
    Driver = "SQL Server",
    Server = "localhost,8888",
    Database = "CompaniesMarketCapDB",
    UID = "sa",
    PWD = password
  )


  print_success(
    "Connected to SQL Server."
  )


  con
}


# ============================================================
# 4. Get Company
# ============================================================

get_company <- function(
  con,
  symbol
) {

  if (
    is.null(symbol) ||
    length(symbol) != 1 ||
    is.na(symbol) ||
    !nzchar(trimws(symbol))
  ) {

    stop(
      "symbol must be a non-empty value."
    )
  }


  company <- dbGetQuery(
    con,
    "
    SELECT
        company_id,
        symbol,
        name
    FROM dbo.Company
    WHERE symbol = ?
    ",
    params = list(symbol)
  )


  if (nrow(company) == 0) {

    stop(
      paste(
        "Company was not found in dbo.Company:",
        symbol
      )
    )
  }


  if (nrow(company) > 1) {

    stop(
      paste(
        "Multiple companies found for symbol:",
        symbol
      )
    )
  }


  company
}


# ============================================================
# 5. Get Latest SQL Market Date
# ============================================================

get_latest_market_date <- function(
  con,
  company_id
) {

  result <- dbGetQuery(
    con,
    "
    SELECT
        MAX(price_date) AS max_date
    FROM dbo.MarketPrice
    WHERE company_id = ?
    ",
    params = list(company_id)
  )


  if (
    nrow(result) == 0 ||
    is.null(result$max_date[[1]]) ||
    is.na(result$max_date[[1]])
  ) {

    return(as.Date(NA))
  }


  as.Date(
    result$max_date[[1]]
  )
}


# ============================================================
# 6. Determine Load Window
# ============================================================

determine_load_window <- function(
  latest_market_date,
  overlap_days = OVERLAP_DAYS
) {

  if (
    length(overlap_days) != 1 ||
    is.na(overlap_days) ||
    overlap_days < 0 ||
    overlap_days != as.integer(overlap_days)
  ) {

    stop(
      "overlap_days must be a non-negative integer."
    )
  }


  # Initial load
  if (is.na(latest_market_date)) {

    return(
      list(
        load_mode = "INITIAL",
        from_date = INITIAL_FROM_DATE,
        latest_sql_date = as.Date(NA)
      )
    )
  }


  # Incremental load
  from_date <- as.Date(latest_market_date) -
    as.integer(overlap_days)


  list(
    load_mode = "INCREMENTAL",
    from_date = from_date,
    latest_sql_date = as.Date(latest_market_date)
  )
}


# ============================================================
# 7. Normalize Market Price Schema
# ============================================================

normalize_market_price <- function(
  price,
  company_id,
  symbol
) {

  required_columns <- c(
    "price_date",
    "open",
    "high",
    "low",
    "close",
    "volume",
    "adjusted"
  )


  missing_columns <- setdiff(
    required_columns,
    names(price)
  )


  if (length(missing_columns) > 0) {

    stop(
      paste(
        "Missing required columns:",
        paste(
          missing_columns,
          collapse = ", "
        )
      )
    )
  }


  price %>%
    transmute(

      company_id = as.integer(
        company_id
      ),

      symbol = as.character(
        symbol
      ),

      price_date = as.Date(
        price_date
      ),

      open = as.numeric(
        open
      ),

      high = as.numeric(
        high
      ),

      low = as.numeric(
        low
      ),

      close = as.numeric(
        close
      ),

      volume = as.numeric(
        volume
      ),

      adjusted = as.numeric(
        adjusted
      )

    ) %>%
    arrange(
      price_date
    )
}


# ============================================================
# 8. Download with tidyquant
# ============================================================

download_with_tq_get <- function(
  symbol,
  from_date
) {

  print_section(
    "Yahoo Finance Download: tq_get()"
  )


  print_info(
    paste(
      "Symbol:",
      symbol
    )
  )


  print_info(
    paste(
      "From date:",
      format_date(from_date)
    )
  )


  captured_warnings <- character(0)
  error_message <- NA_character_


  result <- tryCatch(

    {

      withCallingHandlers(

        tidyquant::tq_get(
          symbol,
          get = "stock.prices",
          from = from_date
        ),

        warning = function(w) {

          captured_warnings <<- c(
            captured_warnings,
            conditionMessage(w)
          )

          invokeRestart(
            "muffleWarning"
          )
        }
      )

    },

    error = function(e) {

      error_message <<- conditionMessage(e)

      NULL
    }
  )


  # Print captured warnings
  if (length(captured_warnings) > 0) {

    unique_warnings <- unique(
      captured_warnings
    )


    print_warning(
      paste(
        "tq_get() generated",
        length(unique_warnings),
        "warning(s)."
      )
    )


    for (warning_message in unique_warnings) {

      print_warning(
        warning_message
      )
    }
  }


  # Return direct error
  if (!is.na(error_message)) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = error_message,
        warnings = captured_warnings
      )
    )
  }


  # tq_get() may return an unexpected object when
  # the underlying Yahoo request fails through warnings.
  if (is.null(result)) {

    combined_error <- paste_download_messages(
      error_message = error_message,
      warnings = captured_warnings,
      fallback_message = "tq_get() returned NULL."
    )


    return(
      list(
        success = FALSE,
        data = NULL,
        error = combined_error,
        warnings = captured_warnings
      )
    )
  }


  if (!is.data.frame(result)) {

    combined_error <- paste_download_messages(
      error_message = error_message,
      warnings = captured_warnings,
      fallback_message = "tq_get() returned an unexpected object."
    )


    return(
      list(
        success = FALSE,
        data = NULL,
        error = combined_error,
        warnings = captured_warnings
      )
    )
  }


  if (nrow(result) == 0) {

    combined_error <- paste_download_messages(
      error_message = error_message,
      warnings = captured_warnings,
      fallback_message = "tq_get() returned zero rows."
    )


    return(
      list(
        success = FALSE,
        data = NULL,
        error = combined_error,
        warnings = captured_warnings
      )
    )
  }


  required_source_columns <- c(
    "date",
    "open",
    "high",
    "low",
    "close",
    "volume",
    "adjusted"
  )


  missing_columns <- setdiff(
    required_source_columns,
    names(result)
  )


  if (length(missing_columns) > 0) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = paste(
          "tq_get() result is missing required columns:",
          paste(
            missing_columns,
            collapse = ", "
          )
        ),
        warnings = captured_warnings
      )
    )
  }


  price_error <- NA_character_


  price <- tryCatch(

    {

      result %>%
        transmute(

          price_date = as.Date(
            date
          ),

          open = as.numeric(
            open
          ),

          high = as.numeric(
            high
          ),

          low = as.numeric(
            low
          ),

          close = as.numeric(
            close
          ),

          volume = as.numeric(
            volume
          ),

          adjusted = as.numeric(
            adjusted
          )
        )

    },

    error = function(e) {

      price_error <<- conditionMessage(e)

      NULL
    }
  )


  if (!is.na(price_error)) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = price_error,
        warnings = captured_warnings
      )
    )
  }


  if (
    is.null(price) ||
    nrow(price) == 0
  ) {

    combined_error <- paste_download_messages(
      error_message = price_error,
      warnings = captured_warnings,
      fallback_message = "tq_get() produced no usable rows."
    )


    return(
      list(
        success = FALSE,
        data = NULL,
        error = combined_error,
        warnings = captured_warnings
      )
    )
  }


  list(
    success = TRUE,
    data = price,
    error = NA_character_,
    warnings = captured_warnings
  )
}


# ============================================================
# 9. Download with quantmod
# ============================================================

download_with_getSymbols <- function(
  symbol,
  from_date
) {

  print_section(
    "Yahoo Finance Download: getSymbols()"
  )


  print_info(
    paste(
      "Symbol:",
      symbol
    )
  )


  print_info(
    paste(
      "From date:",
      format_date(from_date)
    )
  )


  captured_warnings <- character(0)
  error_message <- NA_character_


  x <- tryCatch(

    {

      withCallingHandlers(

        quantmod::getSymbols(
          symbol,
          src = "yahoo",
          from = from_date,
          auto.assign = FALSE
        ),

        warning = function(w) {

          captured_warnings <<- c(
            captured_warnings,
            conditionMessage(w)
          )

          invokeRestart(
            "muffleWarning"
          )
        }
      )

    },

    error = function(e) {

      error_message <<- conditionMessage(e)

      NULL
    }
  )


  # Print captured warnings
  if (length(captured_warnings) > 0) {

    unique_warnings <- unique(
      captured_warnings
    )


    print_warning(
      paste(
        "getSymbols() generated",
        length(unique_warnings),
        "warning(s)."
      )
    )


    for (warning_message in unique_warnings) {

      print_warning(
        warning_message
      )
    }
  }


  if (!is.na(error_message)) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = error_message,
        warnings = captured_warnings
      )
    )
  }


  if (is.null(x)) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = "getSymbols() returned NULL.",
        warnings = captured_warnings
      )
    )
  }


  # Check object type before extraction
  if (!inherits(x, "xts")) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = "getSymbols() returned an invalid xts price series.",
        warnings = captured_warnings
      )
    )
  }


  price_error <- NA_character_


  price <- tryCatch(

    {

      tibble::tibble(

        price_date = as.Date(
          zoo::index(x)
        ),

        open = as.numeric(
          quantmod::Op(x)
        ),

        high = as.numeric(
          quantmod::Hi(x)
        ),

        low = as.numeric(
          quantmod::Lo(x)
        ),

        close = as.numeric(
          quantmod::Cl(x)
        ),

        volume = as.numeric(
          quantmod::Vo(x)
        ),

        adjusted = as.numeric(
          quantmod::Ad(x)
        )
      )

    },

    error = function(e) {

      price_error <<- conditionMessage(e)

      NULL
    }
  )


  if (!is.na(price_error)) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = price_error,
        warnings = captured_warnings
      )
    )
  }


  if (
    is.null(price) ||
    nrow(price) == 0
  ) {

    return(
      list(
        success = FALSE,
        data = NULL,
        error = "getSymbols() returned zero usable rows.",
        warnings = captured_warnings
      )
    )
  }


  list(
    success = TRUE,
    data = price,
    error = NA_character_,
    warnings = captured_warnings
  )
}


# ============================================================
# 10. Build Download Error Message
# ============================================================

paste_download_messages <- function(
  error_message = NA_character_,
  warnings = character(0),
  fallback_message = "Download failed."
) {

  messages <- character(0)


  if (
    !is.null(error_message) &&
    length(error_message) > 0 &&
    !is.na(error_message) &&
    nzchar(trimws(error_message))
  ) {

    messages <- c(
      messages,
      error_message
    )
  }


  if (length(warnings) > 0) {

    messages <- c(
      messages,
      warnings
    )
  }


  messages <- unique(
    messages[
      !is.na(messages) &
      nzchar(trimws(messages))
    ]
  )


  if (length(messages) == 0) {

    return(
      fallback_message
    )
  }


  paste(
    messages,
    collapse = " | "
  )
}


# ============================================================
# 11. Compare Download Results
# ============================================================

compare_download_results <- function(
  tq_data,
  quantmod_data,
  tolerance = 1e-8
) {

  print_header(
    "DOWNLOAD SOURCE COMPARISON"
  )


  if (
    is.null(tq_data) ||
    is.null(quantmod_data)
  ) {

    print_error(
      "One or both download results are unavailable."
    )


    return(
      list(
        comparable = FALSE,
        same_rows = FALSE,
        same_values = FALSE,
        differences = NA_integer_
      )
    )
  }


  tq_data <- tq_data %>%
    arrange(price_date)


  quantmod_data <- quantmod_data %>%
    arrange(price_date)


  joined <- full_join(

    tq_data %>%
      rename_with(
        ~ paste0(.x, "_tq"),
        -price_date
      ),

    quantmod_data %>%
      rename_with(
        ~ paste0(.x, "_quantmod"),
        -price_date
      ),

    by = "price_date"
  )


  compare_numeric <- function(
    x,
    y
  ) {

    both_na <- is.na(x) & is.na(y)

    both_present <- !is.na(x) & !is.na(y)

    valid_equal <- rep(
      FALSE,
      length(x)
    )


    valid_equal[both_na] <- TRUE


    valid_equal[both_present] <- abs(
      x[both_present] -
        y[both_present]
    ) <= tolerance


    valid_equal
  }


  joined <- joined %>%
    mutate(

      open_equal = compare_numeric(
        open_tq,
        open_quantmod
      ),

      high_equal = compare_numeric(
        high_tq,
        high_quantmod
      ),

      low_equal = compare_numeric(
        low_tq,
        low_quantmod
      ),

      close_equal = compare_numeric(
        close_tq,
        close_quantmod
      ),

      volume_equal = compare_numeric(
        volume_tq,
        volume_quantmod
      ),

      adjusted_equal = compare_numeric(
        adjusted_tq,
        adjusted_quantmod
      ),

      value_difference =
        !open_equal |
        !high_equal |
        !low_equal |
        !close_equal |
        !volume_equal |
        !adjusted_equal
    )


  differences <- joined %>%
    filter(
      value_difference
    )


  tq_dates <- unique(
    tq_data$price_date
  )


  quantmod_dates <- unique(
    quantmod_data$price_date
  )


  same_dates <- setequal(
    tq_dates,
    quantmod_dates
  )


  same_rows <- (
    nrow(tq_data) ==
      nrow(quantmod_data)
  ) &&
    same_dates


  same_values <- (
    same_rows &&
      nrow(differences) == 0
  )


  print_info(
    paste(
      "tq_get rows:",
      nrow(tq_data)
    )
  )


  print_info(
    paste(
      "getSymbols rows:",
      nrow(quantmod_data)
    )
  )


  print_info(
    paste(
      "Same date coverage:",
      same_dates
    )
  )


  print_info(
    paste(
      "Different rows:",
      nrow(differences)
    )
  )


  if (same_values) {

    print_success(
      "Both download methods returned matching data."
    )

  } else {

    print_warning(
      "The two download methods returned different results."
    )


    if (nrow(differences) > 0) {

      print(
        head(
          differences,
          20
        )
      )
    }
  }


  list(
    comparable = TRUE,
    same_rows = same_rows,
    same_values = same_values,
    differences = nrow(differences)
  )
}


# ============================================================
# 12. Download Error Classification
# ============================================================

classify_single_download_error <- function(
  error_message
) {

  if (
    is.null(error_message) ||
    length(error_message) == 0 ||
    is.na(error_message) ||
    !nzchar(trimws(error_message))
  ) {

    return("FAILED")
  }


  error_lower <- tolower(
    error_message
  )


  # Clear source-unavailable messages
  source_not_found_patterns <- c(

    "no data",

    "no price data",

    "no price data found",

    "zero rows",

    "zero usable rows",

    "no usable rows",

    "symbol.*not found",

    "not found.*symbol",

    "does not exist",

    "cannot find symbol",

    "not available for this symbol",

    "possibly delisted"

  )


  source_not_found <- any(
    vapply(
      source_not_found_patterns,
      function(pattern) {

        grepl(
          pattern,
          error_lower,
          perl = TRUE
        )

      },
      logical(1)
    )
  )


  if (source_not_found) {

    return(
      "SOURCE_NOT_FOUND"
    )
  }


  # Yahoo's import failure includes the symbol
  # and indicates that Yahoo could not import
  # the requested instrument.
  yahoo_import_failure <- grepl(
    "unable to import.*symbol",
    error_lower,
    perl = TRUE
  )


  if (yahoo_import_failure) {

    return(
      "SOURCE_NOT_FOUND"
    )
  }


  "FAILED"
}


# ============================================================
# 13. Download Yahoo Finance Data
# ============================================================

download_yahoo_price <- function(
  symbol,
  from_date,
  strategy = DOWNLOAD_STRATEGY
) {

  valid_strategies <- c(
    "AUTO",
    "TQ_GET",
    "GETSYMBOLS",
    "COMPARE"
  )


  strategy <- toupper(
    strategy
  )


  if (!strategy %in% valid_strategies) {

    stop(
      paste(
        "Invalid download strategy:",
        strategy,
        "\nAllowed values:",
        paste(
          valid_strategies,
          collapse = ", "
        )
      )
    )
  }


  # ----------------------------------------------------------
  # TQ_GET only
  # ----------------------------------------------------------

  if (strategy == "TQ_GET") {

    result <- download_with_tq_get(
      symbol,
      from_date
    )


    if (!result$success) {

      error_type <- classify_single_download_error(
        result$error
      )


      print_error(
        paste(
          "tq_get() failed:",
          result$error
        )
      )


      return(
        list(
          success = FALSE,
          data = NULL,
          method = NA_character_,
          error = result$error,
          error_type = error_type,
          primary_error_type = error_type,
          fallback_error_type = NA_character_
        )
      )
    }


    print_success(
      "tq_get() download completed."
    )


    return(
      list(
        success = TRUE,
        data = result$data,
        method = "tq_get",
        error = NA_character_,
        error_type = NA_character_,
        primary_error_type = NA_character_,
        fallback_error_type = NA_character_
      )
    )
  }


  # ----------------------------------------------------------
  # GETSYMBOLS only
  # ----------------------------------------------------------

  if (strategy == "GETSYMBOLS") {

    result <- download_with_getSymbols(
      symbol,
      from_date
    )


    if (!result$success) {

      error_type <- classify_single_download_error(
        result$error
      )


      print_error(
        paste(
          "getSymbols() failed:",
          result$error
        )
      )


      return(
        list(
          success = FALSE,
          data = NULL,
          method = NA_character_,
          error = result$error,
          error_type = error_type,
          primary_error_type = NA_character_,
          fallback_error_type = error_type
        )
      )
    }


    print_success(
      "getSymbols() download completed."
    )


    return(
      list(
        success = TRUE,
        data = result$data,
        method = "getSymbols",
        error = NA_character_,
        error_type = NA_character_,
        primary_error_type = NA_character_,
        fallback_error_type = NA_character_
      )
    )
  }


  # ----------------------------------------------------------
  # COMPARE mode
  # ----------------------------------------------------------

  if (strategy == "COMPARE") {

    print_header(
      "COMPARE MODE"
    )


    print_info(
      "Downloading data from both Yahoo Finance methods."
    )


    tq_result <- download_with_tq_get(
      symbol,
      from_date
    )


    quantmod_result <- download_with_getSymbols(
      symbol,
      from_date
    )


    tq_error_type <- NA_character_

    quantmod_error_type <- NA_character_


    if (!tq_result$success) {

      tq_error_type <- classify_single_download_error(
        tq_result$error
      )
    }


    if (!quantmod_result$success) {

      quantmod_error_type <- classify_single_download_error(
        quantmod_result$error
      )
    }


    if (
      !tq_result$success ||
      !quantmod_result$success
    ) {

      print_error(
        "COMPARE mode could not download data from both methods."
      )


      final_error_type <- if (
        tq_error_type == "SOURCE_NOT_FOUND" &&
        quantmod_error_type == "SOURCE_NOT_FOUND"
      ) {

        "SOURCE_NOT_FOUND"

      } else {

        "FAILED"
      }


      return(
        list(
          success = FALSE,
          data = NULL,
          method = "COMPARE",
          comparison = NULL,
          error = paste(
            "tq_get:",
            tq_result$error,
            "| getSymbols:",
            quantmod_result$error
          ),
          error_type = final_error_type,
          primary_error_type = tq_error_type,
          fallback_error_type = quantmod_error_type
        )
      )
    }


    comparison <- compare_download_results(
      tq_data = tq_result$data,
      quantmod_data = quantmod_result$data
    )


    if (
      comparison$same_rows &&
      comparison$same_values
    ) {

      print_success(
        "COMPARE validation passed."
      )


      return(
        list(
          success = TRUE,
          data = tq_result$data,
          method = "COMPARE",
          comparison = comparison,
          error = NA_character_,
          error_type = NA_character_,
          primary_error_type = NA_character_,
          fallback_error_type = NA_character_
        )
      )
    }


    print_error(
      "COMPARE validation failed. Data sources do not match."
    )


    return(
      list(
        success = FALSE,
        data = NULL,
        method = "COMPARE",
        comparison = comparison,
        error = paste(
          "Source comparison failed for",
          symbol
        ),
        error_type = "FAILED",
        primary_error_type = NA_character_,
        fallback_error_type = NA_character_
      )
    )
  }


  # ----------------------------------------------------------
  # AUTO mode
  # ----------------------------------------------------------

  print_header(
    "AUTO DOWNLOAD MODE"
  )


  print_info(
    "Primary source: tq_get()"
  )


  print_info(
    "Fallback source: getSymbols()"
  )


  # Primary source
  tq_result <- download_with_tq_get(
    symbol,
    from_date
  )


  if (tq_result$success) {

    print_success(
      "Primary source succeeded: tq_get()"
    )


    return(
      list(
        success = TRUE,
        data = tq_result$data,
        method = "tq_get",
        error = NA_character_,
        primary_error = NA_character_,
        fallback_error = NA_character_,
        primary_error_type = NA_character_,
        fallback_error_type = NA_character_,
        error_type = NA_character_
      )
    )
  }


  tq_error_type <- classify_single_download_error(
    tq_result$error
  )


  print_warning(
    "Primary source tq_get() failed. Fallback will be attempted."
  )


  print_warning(
    paste(
      "Reason:",
      tq_result$error
    )
  )


  # Fallback source
  quantmod_result <- download_with_getSymbols(
    symbol,
    from_date
  )


  if (quantmod_result$success) {

    print_success(
      "Fallback source succeeded: getSymbols()"
    )


    return(
      list(
        success = TRUE,
        data = quantmod_result$data,
        method = "getSymbols",
        error = NA_character_,
        primary_error = tq_result$error,
        fallback_error = NA_character_,
        primary_error_type = tq_error_type,
        fallback_error_type = NA_character_,
        error_type = NA_character_
      )
    )
  }


  quantmod_error_type <- classify_single_download_error(
    quantmod_result$error
  )


  print_error(
    "Both Yahoo Finance download methods failed."
  )


  # Only classify source unavailable when
  # both download methods agree.
  if (
    tq_error_type == "SOURCE_NOT_FOUND" &&
    quantmod_error_type == "SOURCE_NOT_FOUND"
  ) {

    error_type <- "SOURCE_NOT_FOUND"

  } else {

    error_type <- "FAILED"
  }


  print_warning(
    paste(
      "Primary classification:",
      tq_error_type
    )
  )


  print_warning(
    paste(
      "Fallback classification:",
      quantmod_error_type
    )
  )


  print_warning(
    paste(
      "Download classification:",
      error_type
    )
  )


  list(
    success = FALSE,
    data = NULL,
    method = NA_character_,
    error = paste(
      "tq_get:",
      tq_result$error,
      "| getSymbols:",
      quantmod_result$error
    ),
    primary_error = tq_result$error,
    fallback_error = quantmod_result$error,
    primary_error_type = tq_error_type,
    fallback_error_type = quantmod_error_type,
    error_type = error_type
  )
}


# ============================================================
# 14. Validate Market Price Data
# ============================================================

validate_market_price <- function(
  price
) {

  print_section(
    "DATA VALIDATION"
  )


  if (nrow(price) == 0) {

    stop(
      "Validation failed: no rows available."
    )
  }


  print_info(
    paste(
      "Rows to validate:",
      nrow(price)
    )
  )


  # Missing dates
  missing_dates <- sum(
    is.na(price$price_date)
  )


  if (missing_dates > 0) {

    stop(
      paste(
        "Validation failed:",
        missing_dates,
        "rows have NULL price_date."
      )
    )
  }


  # Missing OHLC
  missing_ohlc <- price %>%
    summarise(
      open = sum(is.na(open)),
      high = sum(is.na(high)),
      low = sum(is.na(low)),
      close = sum(is.na(close))
    )


  total_missing_ohlc <- sum(
    unlist(
      missing_ohlc
    )
  )


  if (total_missing_ohlc > 0) {

    stop(
      paste(
        "Validation failed:",
        total_missing_ohlc,
        "NULL OHLC values detected."
      )
    )
  }


  print_success(
    "Required date and OHLC fields are complete."
  )


  # Duplicate business key
  duplicate_rows <- price %>%
    count(
      company_id,
      price_date
    ) %>%
    filter(
      n > 1
    )


  if (nrow(duplicate_rows) > 0) {

    print_error(
      "Duplicate company_id + price_date detected."
    )


    print(
      duplicate_rows
    )


    stop(
      "Validation failed because duplicate business keys exist."
    )
  }


  print_success(
    "Business key validation passed."
  )


  # OHLC anomaly
  invalid_ohlc <- price %>%
    filter(
      high < low |
      open < low |
      open > high |
      close < low |
      close > high
    )


  ohlc_anomaly_rows <- nrow(
    invalid_ohlc
  )


  if (ohlc_anomaly_rows > 0) {

    print_warning(
      paste(
        "OHLC anomalies detected:",
        ohlc_anomaly_rows,
        "rows."
      )
    )


    print_warning(
      "Source values will be preserved and will NOT be automatically corrected."
    )


    print(
      invalid_ohlc
    )

  } else {

    print_success(
      "OHLC relationship validation passed."
    )
  }


  print_success(
    "Data validation completed."
  )


  list(
    ohlc_anomaly_rows = ohlc_anomaly_rows
  )
}


# ============================================================
# 15. Prepare Staging Table
# ============================================================

prepare_staging_table <- function(
  con
) {

  print_section(
    "SQL STAGING"
  )


  stage_exists <- dbGetQuery(
    con,
    "
    SELECT COUNT(*) AS table_count
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'dbo'
      AND TABLE_NAME = 'MarketPrice_Stage'
    "
  )


  if (
    stage_exists$table_count[[1]] == 0
  ) {

    dbExecute(
      con,
      "
      CREATE TABLE dbo.MarketPrice_Stage (
          company_id INT NOT NULL,
          symbol VARCHAR(50) NOT NULL,
          price_date DATE NOT NULL,
          [open] DECIMAL(18,8) NULL,
          [high] DECIMAL(18,8) NULL,
          [low] DECIMAL(18,8) NULL,
          [close] DECIMAL(18,8) NULL,
          volume BIGINT NULL,
          adjusted DECIMAL(18,8) NULL
      )
      "
    )


    print_success(
      "MarketPrice_Stage table created."
    )

  } else {

    dbExecute(
      con,
      "
      TRUNCATE TABLE dbo.MarketPrice_Stage
      "
    )


    print_info(
      "MarketPrice_Stage table cleared."
    )
  }
}


# ============================================================
# 16. Ensure Business Key
# ============================================================

ensure_business_key <- function(
  con
) {

  print_section(
    "BUSINESS KEY CHECK"
  )


  duplicate_existing <- dbGetQuery(
    con,
    "
    SELECT
        company_id,
        price_date,
        COUNT(*) AS row_count
    FROM dbo.MarketPrice
    GROUP BY
        company_id,
        price_date
    HAVING COUNT(*) > 1
    "
  )


  if (nrow(duplicate_existing) > 0) {

    print_error(
      "Existing duplicate business keys were found in dbo.MarketPrice."
    )


    print(
      head(
        duplicate_existing,
        20
      )
    )


    stop(
      "Cannot continue until existing duplicate keys are resolved."
    )
  }


  dbExecute(
    con,
    "
    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'UX_MarketPrice_Company_Date'
          AND object_id = OBJECT_ID('dbo.MarketPrice')
    )
    BEGIN
        CREATE UNIQUE INDEX UX_MarketPrice_Company_Date
        ON dbo.MarketPrice(company_id, price_date);
    END
    "
  )


  print_success(
    "Business key is ready: company_id + price_date."
  )
}


# ============================================================
# 17. Detect Existing Rows
# ============================================================

detect_existing_rows <- function(
  con,
  price,
  company_id,
  from_date = NULL
) {

  if (is.null(from_date)) {

    existing <- dbGetQuery(
      con,
      "
      SELECT
          company_id,
          CAST(price_date AS DATE) AS price_date
      FROM dbo.MarketPrice
      WHERE company_id = ?
      ",
      params = list(company_id)
    )

  } else {

    existing <- dbGetQuery(
      con,
      "
      SELECT
          company_id,
          CAST(price_date AS DATE) AS price_date
      FROM dbo.MarketPrice
      WHERE company_id = ?
        AND price_date >= ?
      ",
      params = list(
        company_id,
        from_date
      )
    )
  }


  print_section(
    "ROW COMPARISON"
  )


  print_info(
    paste(
      "Existing SQL rows in comparison window:",
      nrow(existing)
    )
  )


  if (nrow(existing) == 0) {

    new_rows <- price

    existing_rows <- price[0, ]

  } else {

    existing$company_id <- as.integer(
      existing$company_id
    )


    existing$price_date <- as.Date(
      existing$price_date
    )


    price_check <- price %>%
      left_join(
        existing %>%
          mutate(
            existing_flag = TRUE
          ),
        by = c(
          "company_id",
          "price_date"
        )
      )


    new_rows <- price_check %>%
      filter(
        is.na(existing_flag)
      )


    existing_rows <- price_check %>%
      filter(
        !is.na(existing_flag)
      )
  }


  print_info(
    paste(
      "New rows:",
      nrow(new_rows)
    )
  )


  print_info(
    paste(
      "Existing rows:",
      nrow(existing_rows)
    )
  )


  list(
    new_rows = new_rows,
    existing_rows = existing_rows
  )
}


# ============================================================
# 18. Execute SQL Upsert
# ============================================================

upsert_market_price <- function(
  con,
  price,
  company_id
) {

  print_header(
    "SQL UPSERT"
  )


  prepare_staging_table(
    con
  )


  staging_duplicates <- price %>%
    count(
      company_id,
      price_date
    ) %>%
    filter(
      n > 1
    )


  if (nrow(staging_duplicates) > 0) {

    stop(
      "Staging data contains duplicate business keys."
    )
  }


  print_info(
    "Writing validated rows to staging table..."
  )


  dbWriteTable(
    con,
    name = DBI::Id(
      schema = "dbo",
      table = "MarketPrice_Stage"
    ),
    value = price,
    append = TRUE
  )


  stage_count <- dbGetQuery(
    con,
    "
    SELECT COUNT(*) AS row_count
    FROM dbo.MarketPrice_Stage
    "
  )


  print_success(
    paste(
      "Staging rows:",
      stage_count$row_count[[1]]
    )
  )


  print_info(
    "Starting SQL transaction..."
  )


  dbBegin(
    con
  )


  tryCatch({

    # Update existing rows
    updated_rows <- dbExecute(
      con,
      "
      UPDATE target
      SET
          target.symbol = source.symbol,
          target.[open] = source.[open],
          target.[high] = source.[high],
          target.[low] = source.[low],
          target.[close] = source.[close],
          target.volume = source.volume,
          target.adjusted = source.adjusted
      FROM dbo.MarketPrice AS target
      INNER JOIN dbo.MarketPrice_Stage AS source
          ON target.company_id = source.company_id
         AND target.price_date = source.price_date
      "
    )


    print_info(
      paste(
        "Existing rows updated:",
        updated_rows
      )
    )


    # Insert new rows
    inserted_rows <- dbExecute(
      con,
      "
      INSERT INTO dbo.MarketPrice (
          company_id,
          symbol,
          price_date,
          [open],
          [high],
          [low],
          [close],
          volume,
          adjusted
      )
      SELECT
          source.company_id,
          source.symbol,
          source.price_date,
          source.[open],
          source.[high],
          source.[low],
          source.[close],
          source.volume,
          source.adjusted
      FROM dbo.MarketPrice_Stage AS source
      WHERE NOT EXISTS (
          SELECT 1
          FROM dbo.MarketPrice AS target
          WHERE target.company_id = source.company_id
            AND target.price_date = source.price_date
      )
      "
    )


    print_info(
      paste(
        "New rows inserted:",
        inserted_rows
      )
    )


    dbCommit(
      con
    )


    print_success(
      "SQL transaction committed successfully."
    )

  }, error = function(e) {

    try(
      dbRollback(con),
      silent = TRUE
    )


    try(
      dbExecute(
        con,
        "TRUNCATE TABLE dbo.MarketPrice_Stage"
      ),
      silent = TRUE
    )


    print_error(
      paste(
        "SQL transaction failed:",
        conditionMessage(e)
      )
    )


    print_warning(
      "All changes from this transaction were rolled back."
    )


    stop(e)
  })


  # Post-upsert validation
  print_section(
    "POST-UPSERT VALIDATION"
  )


  min_date <- min(
    price$price_date
  )


  max_date <- max(
    price$price_date
  )


  final_summary <- dbGetQuery(
    con,
    "
    SELECT
        COUNT(*) AS row_count,
        MIN(price_date) AS min_date,
        MAX(price_date) AS max_date
    FROM dbo.MarketPrice
    WHERE company_id = ?
      AND price_date BETWEEN ? AND ?
    ",
    params = list(
      company_id,
      min_date,
      max_date
    )
  )


  print(
    final_summary
  )


  duplicate_check <- dbGetQuery(
    con,
    "
    SELECT
        company_id,
        price_date,
        COUNT(*) AS row_count
    FROM dbo.MarketPrice
    WHERE company_id = ?
      AND price_date BETWEEN ? AND ?
    GROUP BY
        company_id,
        price_date
    HAVING COUNT(*) > 1
    ",
    params = list(
      company_id,
      min_date,
      max_date
    )
  )


  if (nrow(duplicate_check) > 0) {

    print_error(
      "Duplicate business keys detected after SQL upsert."
    )


    print(
      duplicate_check
    )


    stop(
      "Post-upsert duplicate validation failed."
    )

  } else {

    print_success(
      "Post-upsert duplicate validation passed."
    )
  }


  dbExecute(
    con,
    "TRUNCATE TABLE dbo.MarketPrice_Stage"
  )


  print_success(
    "Staging table cleared."
  )


  list(
    updated_rows = updated_rows,
    inserted_rows = inserted_rows
  )
}


# ============================================================
# 19. Main Ingestion Function
# ============================================================

ingest_market_price <- function(
  con,
  target_symbol,
  write_to_sql = TRUE,
  load_mode = "AUTO",
  overlap_days = OVERLAP_DAYS,
  download_strategy = DOWNLOAD_STRATEGY
) {

  print_header(
    "MARKET PRICE INGESTION"
  )


  valid_load_modes <- c(
    "AUTO",
    "INITIAL",
    "INCREMENTAL"
  )


  load_mode <- toupper(
    load_mode
  )


  download_strategy <- toupper(
    download_strategy
  )


  if (!load_mode %in% valid_load_modes) {

    stop(
      paste(
        "Invalid load_mode:",
        load_mode,
        "\nAllowed values:",
        paste(
          valid_load_modes,
          collapse = ", "
        )
      )
    )
  }


  if (
    !download_strategy %in%
      c(
        "AUTO",
        "TQ_GET",
        "GETSYMBOLS",
        "COMPARE"
      )
  ) {

    stop(
      paste(
        "Invalid download_strategy:",
        download_strategy
      )
    )
  }


  if (
    length(overlap_days) != 1 ||
    is.na(overlap_days) ||
    overlap_days < 0 ||
    overlap_days != as.integer(overlap_days)
  ) {

    stop(
      "overlap_days must be a non-negative integer."
    )
  }


  company <- get_company(
    con,
    target_symbol
  )


  company_id <- company$company_id[[1]]
  symbol <- company$symbol[[1]]
  name <- company$name[[1]]


  print_section(
    "COMPANY"
  )


  print_info(
    paste(
      "Company ID:",
      company_id
    )
  )


  print_info(
    paste(
      "Symbol:",
      symbol
    )
  )


  print_info(
    paste(
      "Name:",
      name
    )
  )


  latest_market_date <- get_latest_market_date(
    con,
    company_id
  )


  print_info(
    paste(
      "Latest SQL market date:",
      format_date(latest_market_date)
    )
  )


  window <- determine_load_window(
    latest_market_date = latest_market_date,
    overlap_days = overlap_days
  )


  actual_load_mode <- window$load_mode
  from_date <- window$from_date


  if (load_mode == "INITIAL") {

    actual_load_mode <- "INITIAL"

    from_date <- INITIAL_FROM_DATE
  }


  if (load_mode == "INCREMENTAL") {

    if (is.na(latest_market_date)) {

      stop(
        paste(
          "INCREMENTAL mode cannot be used because",
          target_symbol,
          "has no existing MarketPrice data."
        )
      )
    }


    actual_load_mode <- "INCREMENTAL"

    from_date <- latest_market_date -
      as.integer(overlap_days)
  }


  print_section(
    "LOAD PLAN"
  )


  print_info(
    paste(
      "Requested mode:",
      load_mode
    )
  )


  print_info(
    paste(
      "Actual mode:",
      actual_load_mode
    )
  )


  print_info(
    paste(
      "Download from:",
      format_date(from_date)
    )
  )


  if (actual_load_mode == "INCREMENTAL") {

    print_info(
      paste(
        "Overlap window:",
        overlap_days,
        "calendar days"
      )
    )
  }


  print_info(
    paste(
      "Download strategy:",
      download_strategy
    )
  )


  # Download
  download_result <- download_yahoo_price(
    symbol = symbol,
    from_date = from_date,
    strategy = download_strategy
  )


  # Handle download failure
  if (!download_result$success) {

    print_warning(
      paste(
        "No usable Yahoo Finance data available for:",
        symbol
      )
    )


    print_warning(
      download_result$error
    )


    final_status <- download_result$error_type


    if (
      is.null(final_status) ||
      is.na(final_status) ||
      !final_status %in%
        c(
          "SOURCE_NOT_FOUND",
          "FAILED"
        )
    ) {

      final_status <- "FAILED"
    }


    if (final_status == "SOURCE_NOT_FOUND") {

      print_warning(
        "Source classification: SOURCE_NOT_FOUND"
      )

    } else {

      print_error(
        "Source classification: FAILED"
      )
    }


    return(
      list(

        company_id = company_id,

        symbol = symbol,

        name = name,

        requested_mode = load_mode,

        actual_mode = actual_load_mode,

        load_mode = actual_load_mode,

        latest_sql_date_before = latest_market_date,

        download_from = from_date,

        download_strategy = download_strategy,

        download_method = download_result$method,

        downloaded_rows = 0L,

        cleaned_rows = 0L,

        removed_rows = 0L,

        new_rows = 0L,

        existing_rows = 0L,

        updated_rows = 0L,

        inserted_rows = 0L,

        ohlc_anomaly_rows = 0L,

        status = final_status,

        error = download_result$error,

        primary_error_type =
          download_result$primary_error_type %||%
          NA_character_,

        fallback_error_type =
          download_result$fallback_error_type %||%
          NA_character_
      )
    )
  }


  price_raw <- download_result$data

  downloaded_rows <- nrow(
    price_raw
  )

  download_method <- download_result$method


  print_section(
    "DOWNLOAD RESULT"
  )


  print_success(
    paste(
      "Download method:",
      download_method
    )
  )


  print_info(
    paste(
      "Downloaded rows:",
      downloaded_rows
    )
  )


  # Normalize
  price <- tryCatch(

    {

      normalize_market_price(
        price = price_raw,
        company_id = company_id,
        symbol = symbol
      )

    },

    error = function(e) {

      stop(
        paste(
          "Market price normalization failed:",
          conditionMessage(e)
        )
      )
    }
  )


  # Remove incomplete OHLC rows
  incomplete_rows <- price %>%
    filter(
      is.na(open) |
      is.na(high) |
      is.na(low) |
      is.na(close)
    )


  if (nrow(incomplete_rows) > 0) {

    print_warning(
      paste(
        "Incomplete OHLC rows detected:",
        nrow(incomplete_rows)
      )
    )


    print(
      incomplete_rows %>%
        select(
          price_date,
          open,
          high,
          low,
          close,
          volume,
          adjusted
        )
    )


    print_warning(
      "Incomplete rows will be excluded from SQL ingestion."
    )


    price <- price %>%
      filter(
        !is.na(open),
        !is.na(high),
        !is.na(low),
        !is.na(close)
      )

  } else {

    print_success(
      "No incomplete OHLC rows detected."
    )
  }


  cleaned_rows <- nrow(
    price
  )


  removed_rows <- downloaded_rows -
    cleaned_rows


  print_info(
    paste(
      "Cleaned rows:",
      cleaned_rows
    )
  )


  print_info(
    paste(
      "Removed rows:",
      removed_rows
    )
  )


  # Handle empty result
  if (cleaned_rows == 0) {

    if (actual_load_mode == "INCREMENTAL") {

      print_warning(
        "No valid rows remain in the incremental download window."
      )


      return(
        list(

          company_id = company_id,

          symbol = symbol,

          name = name,

          requested_mode = load_mode,

          actual_mode = actual_load_mode,

          load_mode = actual_load_mode,

          latest_sql_date_before = latest_market_date,

          download_from = from_date,

          download_strategy = download_strategy,

          download_method = download_method,

          downloaded_rows = downloaded_rows,

          cleaned_rows = 0L,

          removed_rows = removed_rows,

          new_rows = 0L,

          existing_rows = 0L,

          updated_rows = 0L,

          inserted_rows = 0L,

          ohlc_anomaly_rows = 0L,

          status = "NO_NEW_DATA",

          error = NA_character_,

          primary_error_type = NA_character_,

          fallback_error_type = NA_character_
        )
      )
    }


    stop(
      paste(
        "No valid market price rows available for:",
        target_symbol
      )
    )
  }


  # Validate
  validation <- validate_market_price(
    price
  )


  ohlc_anomaly_rows <- validation$ohlc_anomaly_rows


  # Data summary
  print_section(
    "DATA SUMMARY"
  )


  summary_data <- price %>%
    summarise(
      rows = n(),
      min_date = min(price_date),
      max_date = max(price_date),
      min_close = min(close),
      max_close = max(close)
    )


  print(
    summary_data
  )


  # Detect existing rows
  comparison <- detect_existing_rows(
    con = con,
    price = price,
    company_id = company_id,
    from_date = from_date
  )


  updated_rows <- 0L
  inserted_rows <- 0L


  # SQL write
  if (write_to_sql) {

    print_info(
      "SQL write mode: ENABLED"
    )


    ensure_business_key(
      con
    )


    sql_result <- upsert_market_price(
      con = con,
      price = price,
      company_id = company_id
    )


    updated_rows <- sql_result$updated_rows
    inserted_rows <- sql_result$inserted_rows

  } else {

    print_header(
      "DRY RUN"
    )


    print_warning(
      "SQL write is disabled."
    )


    print_info(
      "No data will be written to dbo.MarketPrice."
    )
  }


  # Determine final status
  if (ohlc_anomaly_rows > 0) {

    final_status <- "OHLC_WARNING"

  } else if (
    nrow(comparison$new_rows) == 0 &&
    !write_to_sql
  ) {

    final_status <- "NO_NEW_DATA"

  } else if (
    nrow(comparison$new_rows) == 0 &&
    write_to_sql &&
    updated_rows == 0 &&
    inserted_rows == 0
  ) {

    final_status <- "NO_NEW_DATA"

  } else {

    final_status <- "SUCCESS"
  }


  print_header(
    "INGESTION COMPLETED"
  )


  if (final_status == "SUCCESS") {

    print_success(
      "Market price ingestion completed successfully."
    )

  } else {

    print_warning(
      paste(
        "Market price ingestion completed with status:",
        final_status
      )
    )
  }


  list(

    company_id = company_id,

    symbol = symbol,

    name = name,

    requested_mode = load_mode,

    actual_mode = actual_load_mode,

    load_mode = actual_load_mode,

    latest_sql_date_before = latest_market_date,

    download_from = from_date,

    download_strategy = download_strategy,

    download_method = download_method,

    downloaded_rows = downloaded_rows,

    cleaned_rows = cleaned_rows,

    removed_rows = removed_rows,

    new_rows = nrow(
      comparison$new_rows
    ),

    existing_rows = nrow(
      comparison$existing_rows
    ),

    updated_rows = updated_rows,

    inserted_rows = inserted_rows,

    ohlc_anomaly_rows = ohlc_anomaly_rows,

    status = final_status,

    error = NA_character_,

    primary_error_type = NA_character_,

    fallback_error_type = NA_character_
  )
}


# ============================================================
# 20. Print Final Result
# ============================================================

print_ingestion_result <- function(
  result
) {

  print_header(
    "FINAL INGESTION RESULT"
  )


  cat(
    "Company ID:              ",
    result$company_id,
    "\n",
    sep = ""
  )


  cat(
    "Symbol:                  ",
    result$symbol,
    "\n",
    sep = ""
  )


  cat(
    "Company Name:            ",
    result$name,
    "\n",
    sep = ""
  )


  cat(
    "Requested Mode:          ",
    result$requested_mode,
    "\n",
    sep = ""
  )


  cat(
    "Actual Mode:             ",
    result$actual_mode,
    "\n",
    sep = ""
  )


  cat(
    "Download Strategy:       ",
    result$download_strategy,
    "\n",
    sep = ""
  )


  cat(
    "Download Method:         ",
    result$download_method,
    "\n",
    sep = ""
  )


  cat(
    "Latest SQL Date Before:  ",
    format_date(
      result$latest_sql_date_before
    ),
    "\n",
    sep = ""
  )


  cat(
    "Download From:           ",
    format_date(
      result$download_from
    ),
    "\n",
    sep = ""
  )


  cat(
    "Downloaded Rows:         ",
    result$downloaded_rows,
    "\n",
    sep = ""
  )


  cat(
    "Cleaned Rows:            ",
    result$cleaned_rows,
    "\n",
    sep = ""
  )


  cat(
    "Removed Rows:            ",
    result$removed_rows,
    "\n",
    sep = ""
  )


  cat(
    "New Rows:                ",
    result$new_rows,
    "\n",
    sep = ""
  )


  cat(
    "Existing Rows:           ",
    result$existing_rows,
    "\n",
    sep = ""
  )


  cat(
    "Updated Rows:            ",
    result$updated_rows,
    "\n",
    sep = ""
  )


  cat(
    "Inserted Rows:           ",
    result$inserted_rows,
    "\n",
    sep = ""
  )


  cat(
    "OHLC Anomaly Rows:       ",
    result$ohlc_anomaly_rows,
    "\n",
    sep = ""
  )


  cat(
    "Status:                  ",
    result$status,
    "\n",
    sep = ""
  )


  if (
    !is.null(result$error) &&
    !is.na(result$error) &&
    nzchar(result$error)
  ) {

    cat(
      "Error:                   ",
      result$error,
      "\n",
      sep = ""
    )
  }


  if (
    !is.null(result$primary_error_type) &&
    !is.na(result$primary_error_type) &&
    nzchar(result$primary_error_type)
  ) {

    cat(
      "Primary Error Type:      ",
      result$primary_error_type,
      "\n",
      sep = ""
    )
  }


  if (
    !is.null(result$fallback_error_type) &&
    !is.na(result$fallback_error_type) &&
    nzchar(result$fallback_error_type)
  ) {

    cat(
      "Fallback Error Type:     ",
      result$fallback_error_type,
      "\n",
      sep = ""
    )
  }


  print_section(
    "STATUS INTERPRETATION"
  )


  status_message <- switch(

    result$status,

    SUCCESS =
      "All validation checks passed and ingestion completed.",

    OHLC_WARNING =
      "Data was ingested, but one or more source OHLC anomalies were detected. Source values were preserved.",

    NO_NEW_DATA =
      "No new market dates were detected in the incremental window. Existing overlap rows were available for reprocessing.",

    SOURCE_NOT_FOUND =
      "No usable Yahoo Finance market data was available for this symbol using the configured download methods.",

    FAILED =
      "Ingestion failed because of a pipeline, validation, database, or unexpected runtime error.",

    paste(
      "Unknown status:",
      result$status
    )
  )


  cat(
    status_message,
    "\n"
  )
}


# ============================================================
# 21. Direct Test Runner
# ============================================================
#
# This file intentionally does NOT execute ingestion automatically.
# Use a separate command or runner script to call ingest_market_price().
#
# Example:
#
# TEST_SYMBOL <- "IHC.AE"
#
# source("r/1_ingest_market_price.R")
#
# con <- NULL
#
# tryCatch({
#
#   con <- connect_db()
#
#   result <- ingest_market_price(
#     con = con,
#     target_symbol = TEST_SYMBOL,
#     write_to_sql = WRITE_TO_SQL,
#     load_mode = "AUTO",
#     overlap_days = OVERLAP_DAYS,
#     download_strategy = DOWNLOAD_STRATEGY
#   )
#
#   print_ingestion_result(result)
#
# }, error = function(e) {
#
#   print_header("INGESTION FAILED")
#   print_error(conditionMessage(e))
#
# }, finally = {
#
#   if (!is.null(con) && dbIsValid(con)) {
#
#     dbDisconnect(con)
#
#     print_success(
#       "Database connection closed."
#     )
#   }
# })