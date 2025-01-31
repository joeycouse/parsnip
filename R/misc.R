#' Prepend a new class
#'
#' This adds an extra class to a base class of "model_spec".
#'
#' @param prefix A character string for a class.
#' @return A character vector.
#' @keywords internal
#' @export
make_classes <- function(prefix) {
  c(prefix, "model_spec")
}

#' Check to ensure that ellipses are empty
#' @param ... Extra arguments.
#' @return If an error is not thrown (from non-empty ellipses), a NULL list.
#' @keywords internal
#' @export
check_empty_ellipse <- function(...) {
  terms <- quos(...)
  if (!is_empty(terms)) {
    rlang::abort("Please pass other arguments to the model function via `set_engine()`.")
  }
  terms
}

is_missing_arg <- function(x) {
  identical(x, quote(missing_arg()))
}

model_info_table <-
  utils::read.delim(system.file("models.tsv", package = "parsnip"))

# given a model object, return TRUE if:
# * the model is supported without extensions
# * the model needs an extension and it is loaded
#
# return FALSE if:
# * the model needs an extension and it is _not_ loaded
has_loaded_implementation <- function(spec_, engine_, mode_) {
  if (isFALSE(mode_ %in% c("regression", "censored regression", "classification"))) {
    mode_ <- c("regression", "censored regression", "classification")
  }
  eng_cond <- if (is.null(engine_)) {
    TRUE
  } else {
    quote(engine == engine_)
  }

  avail <-
    get_from_env(spec_) %>%
    dplyr::filter(mode %in% mode_, !!eng_cond)
  pars <-
    model_info_table %>%
    dplyr::filter(model == spec_, !!eng_cond, mode %in% mode_, is.na(pkg))

  if (nrow(pars) > 0 || nrow(avail) > 0) {
    return(TRUE)
  }

  FALSE
}

is_printable_spec <- function(x) {
  !is.null(x$method$fit$args) &&
    has_loaded_implementation(class(x)[1], x$engine, x$mode)
}

# construct a message informing the user that there are no
# implementations for the current model spec / mode / engine.
#
# if there's a "pre-registered" extension supporting that setup,
# nudge the user to install/load it.
inform_missing_implementation <- function(spec_, engine_, mode_) {
  avail <-
    show_engines(spec_) %>%
    dplyr::filter(mode == mode_, engine == engine_)
  all <-
    model_info_table %>%
    dplyr::filter(model == spec_, mode == mode_, engine == engine_, !is.na(pkg)) %>%
    dplyr::select(-model)

  if (identical(mode_, "unknown")) {
    mode_ <- ""
  }

  msg <-
    glue::glue(
      "parsnip could not locate an implementation for `{spec_}` {mode_} model \\
       specifications using the `{engine_}` engine."
    )

  if (nrow(avail) == 0 && nrow(all) > 0) {
    msg <-
      c(
        msg,
        i = paste0("The parsnip extension package ", all$pkg[[1]],
                   " implements support for this specification."),
        i = "Please install (if needed) and load to continue.",
        ""
      )
  }

  msg
}


#' Print the model call
#'
#' @param x A "model_spec" object.
#' @return A character string.
#' @keywords internal
#' @export
show_call <- function(object) {
  object$method$fit$args <-
    map(object$method$fit$args, convert_arg)

  call2(object$method$fit$func["fun"],
    !!!object$method$fit$args,
    .ns = object$method$fit$func["pkg"]
  )
}

convert_arg <- function(x) {
  if (is_quosure(x)) {
    quo_get_expr(x)
  } else {
    x
  }
}

levels_from_formula <- function(f, dat) {
  if (inherits(dat, "tbl_spark")) {
    res <- NULL
  } else {
    res <- levels(eval_tidy(f[[2]], dat))
  }
  res
}

#' @export
#' @keywords internal
#' @rdname add_on_exports
show_fit <- function(model, eng) {
  mod <- translate(x = model, engine = eng)
  fit_call <- show_call(mod)
  call_text <- deparse(fit_call)
  call_text <- paste0(call_text, collapse = "\n")
  paste0(
    "\\preformatted{\n",
    call_text,
    "\n}\n\n"
  )
}

# Check non-translated core arguments
# Each model has its own definition of this
check_args <- function(object) {
  UseMethod("check_args")
}

check_args.default <- function(object) {
  invisible(object)
}

# ------------------------------------------------------------------------------

# copied form recipes

names0 <- function(num, prefix = "x") {
  if (num < 1) {
    rlang::abort("`num` should be > 0.")
  }
  ind <- format(1:num)
  ind <- gsub(" ", "0", ind)
  paste0(prefix, ind)
}


# ------------------------------------------------------------------------------

#' @export
#' @keywords internal
#' @rdname add_on_exports
update_dot_check <- function(...) {
  dots <- enquos(...)

  if (length(dots) > 0) {
    rlang::abort(
      glue::glue(
        "Extra arguments will be ignored: ",
        glue::glue_collapse(glue::glue("`{names(dots)}`"), sep = ", ")
      )
    )
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------

#' @export
#' @keywords internal
#' @rdname add_on_exports
new_model_spec <- function(cls, args, eng_args, mode, method, engine,
                           check_missing_spec = TRUE) {
  check_spec_mode_engine_val(cls, engine, mode)

  if ((!has_loaded_implementation(cls, engine, mode)) && check_missing_spec) {
    rlang::inform(inform_missing_implementation(cls, engine, mode))
  }

  out <- list(
    args = args, eng_args = eng_args,
    mode = mode, method = method, engine = engine
  )
  class(out) <- make_classes(cls)
  out
}

# ------------------------------------------------------------------------------

check_outcome <- function(y, spec) {
  if (spec$mode == "unknown") {
    return(invisible(NULL))
  } else if (spec$mode == "regression") {
    if (!all(map_lgl(y, is.numeric))) {
      rlang::abort("For a regression model, the outcome should be numeric.")
    }
  } else if (spec$mode == "classification") {
    if (!all(map_lgl(y, is.factor))) {
      rlang::abort("For a classification model, the outcome should be a factor.")
    }
  }
  invisible(NULL)
}

# ------------------------------------------------------------------------------

#' @export
#' @keywords internal
#' @rdname add_on_exports
check_final_param <- function(x) {
  if (is.null(x)) {
    return(invisible(x))
  }
  if (!is.list(x) & !tibble::is_tibble(x)) {
    rlang::abort("The parameter object should be a list or tibble")
  }
  if (tibble::is_tibble(x) && nrow(x) > 1) {
    rlang::abort("The parameter tibble should have a single row.")
  }
  if (tibble::is_tibble(x)) {
    x <- as.list(x)
  }
  if (length(names) == 0 || any(names(x) == "")) {
    rlang::abort("All values in `parameters` should have a name.")
  }

  invisible(x)
}

#' @export
#' @keywords internal
#' @rdname add_on_exports
update_main_parameters <- function(args, param) {
  if (length(param) == 0) {
    return(args)
  }
  if (length(args) == 0) {
    return(param)
  }

  # In case an engine argument is included:
  has_extra_args <- !(names(param) %in% names(args))
  extra_args <- names(param)[has_extra_args]
  if (any(has_extra_args)) {
    rlang::abort(
      paste(
        "At least one argument is not a main argument:",
        paste0("`", extra_args, "`", collapse = ", ")
      )
    )
  }
  param <- param[!has_extra_args]

  args <- utils::modifyList(args, param)
}

#' @export
#' @keywords internal
#' @rdname add_on_exports
update_engine_parameters <- function(eng_args, fresh, ...) {
  dots <- enquos(...)

  ## only update from dots when there are eng args in original model spec
  if (is_null(eng_args) || (fresh && length(dots) == 0)) {
    ret <- NULL
  } else {
    ret <- utils::modifyList(eng_args, dots)
  }

  has_extra_dots <- !(names(dots) %in% names(eng_args))
  dots <- dots[has_extra_dots]
  update_dot_check(!!!dots)

  ret
}

# ------------------------------------------------------------------------------
# Since stan changed the function interface
#' Wrapper for stan confidence intervals
#' @param object A stan model fit
#' @param newdata A data set.
#' @export
#' @keywords internal
stan_conf_int <- function(object, newdata) {
  check_installs(list(method = list(libs = "rstanarm")))
  if (utils::packageVersion("rstanarm") >= "2.21.1") {
    fn <- rlang::call2("posterior_epred",
      .ns = "rstanarm",
      object = expr(object),
      newdata = expr(newdata),
      seed = expr(sample.int(10^5, 1))
    )
  } else {
    fn <- rlang::call2("posterior_linpred",
      .ns = "rstanarm",
      object = expr(object),
      newdata = expr(newdata),
      transform = TRUE,
      seed = expr(sample.int(10^5, 1))
    )
  }
  rlang::eval_tidy(fn)
}

# ------------------------------------------------------------------------------


#' Helper functions for checking the penalty of glmnet models
#'
#' @description
#' These functions are for developer use.
#'
#' `.check_glmnet_penalty_fit()` checks that the model specification for fitting a
#' glmnet model contains a single value.
#'
#' `.check_glmnet_penalty_predict()` checks that the penalty value used for prediction is valid.
#' If called by `predict()`, it needs to be a single value. Multiple values are
#' allowed for `multi_predict()`.
#'
#' @param x An object of class `model_spec`.
#' @rdname glmnet_helpers
#' @keywords internal
#' @export
.check_glmnet_penalty_fit <- function(x) {
  pen <- rlang::eval_tidy(x$args$penalty)

  if (length(pen) != 1) {
    rlang::abort(c(
      "For the glmnet engine, `penalty` must be a single number (or a value of `tune()`).",
      glue::glue("There are {length(pen)} values for `penalty`."),
      "To try multiple values for total regularization, use the tune package.",
      "To predict multiple penalties, use `multi_predict()`"
    ))
  }
}

#' @param penalty A penalty value to check.
#' @param object An object of class `model_fit`.
#' @param multi A logical indicating if multiple values are allowed.
#'
#' @rdname glmnet_helpers
#' @keywords internal
#' @export
.check_glmnet_penalty_predict <- function(penalty = NULL, object, multi = FALSE) {
  if (is.null(penalty)) {
    penalty <- object$fit$lambda
  }

  # when using `predict()`, allow for a single lambda
  if (!multi) {
    if (length(penalty) != 1) {
      rlang::abort(
        glue::glue(
          "`penalty` should be a single numeric value. `multi_predict()` ",
          "can be used to get multiple predictions per row of data.",
        )
      )
    }
  }

  if (length(object$fit$lambda) == 1 && penalty != object$fit$lambda) {
    rlang::abort(
      glue::glue(
        "The glmnet model was fit with a single penalty value of ",
        "{object$fit$lambda}. Predicting with a value of {penalty} ",
        "will give incorrect results from `glmnet()`."
      )
    )
  }

  penalty
}


check_case_weights <- function(x, spec) {
  if (is.null(x) | spec$engine == "spark") {
    return(invisible(NULL))
  }
  if (!hardhat::is_case_weights(x)) {
    rlang::abort("'case_weights' should be a single numeric vector of class 'hardhat_case_weights'.")
  }
  allowed <- case_weights_allowed(spec)
  if (!allowed) {
    rlang::abort("Case weights are not enabled by the underlying model implementation.")
  }
  invisible(NULL)
}
