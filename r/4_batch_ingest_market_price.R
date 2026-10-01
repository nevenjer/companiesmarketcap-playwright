# ==========================================================
# Project 18.2
# Batch Market Price Ingestion
# ==========================================================

source("r/1_ingest_market_price.R")


# ==========================================================
# 1. Batch Configuration
# ==========================================================

WRITE_TO_SQL <- TRUE

BATCH_SCOPE <- "ALL"  # Options: "TEST" or "ALL"
TEST_LIMIT <- 100

LOAD_MODE <- "AUTO"

DOWNLOAD_STRATEGY <- "AUTO"

OVERLAP_DAYS <- 5


# ==========================================================
# 2. Validate Configuration
# ==========================================================

if (!BATCH_SCOPE %in% c("TEST", "ALL")) {
  stop("BATCH_SCOPE must be TEST or ALL.")
}

if (!LOAD_MODE %in% c("AUTO", "INITIAL", "INCREMENTAL")) {
  stop("LOAD_MODE must be AUTO, INITIAL, or INCREMENTAL.")
}

if (!DOWNLOAD_STRATEGY %in% c("AUTO", "TQ_GET", "GETSYMBOLS", "COMPARE")) {
  stop(
    "DOWNLOAD_STRATEGY must be AUTO, TQ_GET, GETSYMBOLS, or COMPARE."
  )
}

if (TEST_LIMIT < 1) {
  stop("TEST_LIMIT must be greater than 0.")
}

if (OVERLAP_DAYS < 0) {
  stop("OVERLAP_DAYS must be >= 0.")
}


# ==========================================================
# 3. Connect Database
# ==========================================================

con <- connect_db()


# ==========================================================
# 4. Run Batch
# ==========================================================

tryCatch({

  batch_start_time <- Sys.time()


  # --------------------------------------------------------
  # 4.1 Ensure Business Key
  # --------------------------------------------------------

  ensure_business_key(con)


  # --------------------------------------------------------
  # 4.2 Load Company List
  # --------------------------------------------------------

  if (BATCH_SCOPE == "TEST") {

    companies <- DBI::dbGetQuery(
      con,
      paste0(
        "SELECT TOP ",
        TEST_LIMIT,
        " company_id, symbol, name ",
        "FROM dbo.Company ",
        "ORDER BY company_id"
      )
    )

  } else {

    companies <- DBI::dbGetQuery(
      con,
      paste0(
        "SELECT company_id, symbol, name ",
        "FROM dbo.Company ",
        "ORDER BY company_id"
      )
    )
  }


  # --------------------------------------------------------
  # 4.3 Validate Company List
  # --------------------------------------------------------

  if (nrow(companies) == 0) {
    stop("No companies found in dbo.Company.")
  }


  # --------------------------------------------------------
  # 4.4 Batch Header
  # --------------------------------------------------------

  print_header("BATCH MARKET PRICE INGESTION")

  print_info(
    paste0(
      "Scope: ",
      BATCH_SCOPE
    )
  )

  print_info(
    paste0(
      "Companies: ",
      nrow(companies)
    )
  )

  print_info(
    paste0(
      "Load mode: ",
      LOAD_MODE
    )
  )

  print_info(
    paste0(
      "Download strategy: ",
      DOWNLOAD_STRATEGY
    )
  )

  print_info(
    paste0(
      "Overlap days: ",
      OVERLAP_DAYS
    )
  )

  print_info(
    paste0(
      "Write to SQL: ",
      WRITE_TO_SQL
    )
  )


  # --------------------------------------------------------
  # 4.5 Company List
  # --------------------------------------------------------

  print_section("COMPANY LIST")

  display_limit <- min(20, nrow(companies))

  print(
    companies[
      seq_len(display_limit),
      c("company_id", "symbol", "name")
    ]
  )

  if (nrow(companies) > display_limit) {

    print_info(
      paste0(
        "... ",
        nrow(companies) - display_limit,
        " additional companies will be processed."
      )
    )
  }


  # --------------------------------------------------------
  # 4.6 Process Companies
  # --------------------------------------------------------

  results <- vector(
    "list",
    nrow(companies)
  )


  for (i in seq_len(nrow(companies))) {

    company_id <- companies$company_id[i]
    symbol <- companies$symbol[i]
    name <- companies$name[i]

    company_start_time <- Sys.time()


    print_header(
      paste0(
        "COMPANY ",
        i,
        "/",
        nrow(companies),
        " | ",
        symbol
      )
    )

    print_info(
      paste0(
        "Company ID: ",
        company_id
      )
    )

    print_info(
      paste0(
        "Name: ",
        name
      )
    )


    # ------------------------------------------------------
    # Process One Company
    # ------------------------------------------------------

    result <- tryCatch({

      ingest_market_price(
        con = con,
        target_symbol = symbol,
        write_to_sql = WRITE_TO_SQL,
        load_mode = LOAD_MODE,
        overlap_days = OVERLAP_DAYS,
        download_strategy = DOWNLOAD_STRATEGY
      )

    }, error = function(e) {

      print_error(
        paste0(
          "Company failed: ",
          conditionMessage(e)
        )
      )


      # Keep result schema consistent
      list(
        company_id = company_id,
        symbol = symbol,
        name = name,

        requested_mode = LOAD_MODE,
        actual_mode = NA_character_,

        download_strategy = DOWNLOAD_STRATEGY,
        download_method = NA_character_,

        download_from = as.Date(NA),
        download_to = as.Date(NA),

        downloaded_rows = 0L,
        cleaned_rows = 0L,
        removed_rows = 0L,

        new_rows = 0L,
        existing_rows = 0L,
        updated_rows = 0L,
        inserted_rows = 0L,

        ohlc_anomaly_rows = 0L,

        status = "FAILED",

        error = conditionMessage(e)
      )
    })


    # ------------------------------------------------------
    # Store Timing
    # ------------------------------------------------------

    company_elapsed <- as.numeric(
      difftime(
        Sys.time(),
        company_start_time,
        units = "secs"
      )
    )


    result$elapsed_seconds <- company_elapsed


    # ------------------------------------------------------
    # Store Company Result
    # ------------------------------------------------------

    results[[i]] <- result


    # ------------------------------------------------------
    # Print Result
    # ------------------------------------------------------

    print_info(
      paste0(
        "Company elapsed: ",
        round(company_elapsed, 1),
        " sec"
      )
    )

    print_info(
      paste0(
        "Status: ",
        result$status
      )
    )
  }


  # ========================================================
  # 5. Combine Results
  # ========================================================

  results_df <- dplyr::bind_rows(results)


  # ========================================================
  # 6. Batch Summary
  # ========================================================

  batch_elapsed <- as.numeric(
    difftime(
      Sys.time(),
      batch_start_time,
      units = "secs"
    )
  )


  print_header("BATCH SUMMARY")


  # --------------------------------------------------------
  # 6.1 Status Counts
  # --------------------------------------------------------

  success_count <- sum(
    results_df$status == "SUCCESS",
    na.rm = TRUE
  )

  no_new_data_count <- sum(
    results_df$status == "NO_NEW_DATA",
    na.rm = TRUE
  )

  ohlc_warning_count <- sum(
    results_df$status == "OHLC_WARNING",
    na.rm = TRUE
  )

  source_not_found_count <- sum(
    results_df$status == "SOURCE_NOT_FOUND",
    na.rm = TRUE
  )

  failed_count <- sum(
    results_df$status == "FAILED",
    na.rm = TRUE
  )


  print_section("STATUS SUMMARY")

  cat(
    "SUCCESS:          ",
    success_count,
    "\n"
  )

  cat(
    "NO_NEW_DATA:      ",
    no_new_data_count,
    "\n"
  )

  cat(
    "OHLC_WARNING:     ",
    ohlc_warning_count,
    "\n"
  )

  cat(
    "SOURCE_NOT_FOUND: ",
    source_not_found_count,
    "\n"
  )

  cat(
    "FAILED:           ",
    failed_count,
    "\n"
  )


  # ========================================================
  # 7. Data Row Summary
  # ========================================================

  print_section("ROW SUMMARY")


  total_downloaded <- sum(
    results_df$downloaded_rows,
    na.rm = TRUE
  )

  total_cleaned <- sum(
    results_df$cleaned_rows,
    na.rm = TRUE
  )

  total_removed <- sum(
    results_df$removed_rows,
    na.rm = TRUE
  )

  total_new <- sum(
    results_df$new_rows,
    na.rm = TRUE
  )

  total_existing <- sum(
    results_df$existing_rows,
    na.rm = TRUE
  )

  total_updated <- sum(
    results_df$updated_rows,
    na.rm = TRUE
  )

  total_inserted <- sum(
    results_df$inserted_rows,
    na.rm = TRUE
  )

  total_ohlc_anomalies <- sum(
    results_df$ohlc_anomaly_rows,
    na.rm = TRUE
  )


  cat(
    "Downloaded rows: ",
    total_downloaded,
    "\n"
  )

  cat(
    "Cleaned rows:    ",
    total_cleaned,
    "\n"
  )

  cat(
    "Removed rows:    ",
    total_removed,
    "\n"
  )

  cat(
    "New rows:        ",
    total_new,
    "\n"
  )

  cat(
    "Existing rows:   ",
    total_existing,
    "\n"
  )

  cat(
    "Updated rows:    ",
    total_updated,
    "\n"
  )

  cat(
    "Inserted rows:   ",
    total_inserted,
    "\n"
  )

  cat(
    "OHLC anomalies:  ",
    total_ohlc_anomalies,
    "\n"
  )


  # ========================================================
  # 8. Download Method Summary
  # ========================================================

  print_section("DOWNLOAD METHOD SUMMARY")


  if ("download_method" %in% names(results_df)) {

    method_summary <- table(
      results_df$download_method,
      useNA = "ifany"
    )

    print(method_summary)
  }


  # ========================================================
  # 9. Failed Companies
  # ========================================================

  if (failed_count > 0) {

    print_section("FAILED COMPANIES")

    failed_companies <- results_df[
      results_df$status == "FAILED",
      c(
        "company_id",
        "symbol",
        "name",
        "error"
      ),
      drop = FALSE
    ]

    print(failed_companies)
  }


  # ========================================================
  # 10. Source Not Found
  # ========================================================

  if (source_not_found_count > 0) {

    print_section("SOURCE NOT FOUND")

    source_not_found <- results_df[
      results_df$status == "SOURCE_NOT_FOUND",
      c(
        "company_id",
        "symbol",
        "name",
        "error"
      ),
      drop = FALSE
    ]

    print(source_not_found)
  }


  # ========================================================
  # 11. OHLC Warnings
  # ========================================================

  if (ohlc_warning_count > 0) {

    print_section("OHLC WARNINGS")

    ohlc_warnings <- results_df[
      results_df$status == "OHLC_WARNING",
      c(
        "company_id",
        "symbol",
        "name",
        "ohlc_anomaly_rows"
      ),
      drop = FALSE
    ]

    print(ohlc_warnings)
  }


  # ========================================================
  # 12. Batch Timing
  # ========================================================

  print_section("BATCH TIMING")

  print_info(
    paste0(
      "Batch elapsed: ",
      round(batch_elapsed, 1),
      " seconds"
    )
  )

  print_info(
    paste0(
      "Companies processed: ",
      nrow(results_df)
    )
  )


  # ========================================================
  # 13. Final Result Table
  # ========================================================

  print_section("RESULT TABLE")


  result_columns <- c(
    "company_id",
    "symbol",
    "name",
    "requested_mode",
    "actual_mode",
    "download_strategy",
    "download_method",
    "downloaded_rows",
    "cleaned_rows",
    "new_rows",
    "existing_rows",
    "updated_rows",
    "inserted_rows",
    "ohlc_anomaly_rows",
    "status",
    "elapsed_seconds"
  )


  result_columns <- intersect(
    result_columns,
    names(results_df)
  )


  print(
    results_df[
      ,
      result_columns,
      drop = FALSE
    ]
  )


  # ========================================================
  # 14. Final Batch Message
  # ========================================================

  print_header("BATCH COMPLETED")

  print_success(
    paste0(
      "Companies processed: ",
      nrow(results_df)
    )
  )

  print_success(
    paste0(
      "Success: ",
      success_count
    )
  )

  print_info(
    paste0(
      "No new data: ",
      no_new_data_count
    )
  )

  print_warning(
    paste0(
      "OHLC warnings: ",
      ohlc_warning_count
    )
  )

  print_warning(
    paste0(
      "Source not found: ",
      source_not_found_count
    )
  )

  if (failed_count > 0) {

    print_error(
      paste0(
        "Failed: ",
        failed_count
      )
    )

  } else {

    print_success(
      "Failed: 0"
    )
  }

  print_info(
    paste0(
      "Batch elapsed: ",
      round(batch_elapsed, 1),
      " seconds"
    )
  )


}, finally = {

  # ========================================================
  # 15. Disconnect Database
  # ========================================================

  if (DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con)
  }

})
