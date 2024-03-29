#' Search for matches to a regular expression
#' 
#' Search a character vector, or the content of a file or connection, for one
#' or more matches to an Oniguruma-compatible regular expression. Printing and
#' indexing methods are available for the results. \code{ore_match} is an alias
#' for \code{ore_search}.
#' 
#' @param regex A single character string or object of class \code{"ore"}. In
#'   the former case, this will first be passed through \code{\link{ore}}.
#' @param text A vector of strings to match against, or a connection, or the
#'   result of a call to \code{\link{ore_file}} to search in a file. In the
#'   latter case, match offsets will be relative to the file's encoding.
#' @param all If \code{TRUE}, then all matches within each element of
#'   \code{text} will be found. Otherwise, the search will stop at the first
#'   match.
#' @param start An optional vector of offsets (in characters) at which to start
#'   searching. Will be recycled to the length of \code{text}.
#' @param simplify If \code{TRUE}, an object of class \code{"orematch"} will
#'   be returned if \code{text} is of length 1. Otherwise, a list of such
#'   objects, with class \code{"orematches"}, will always be returned. When
#'   printing \code{"orematches"} objects, this controls whether or not to omit
#'   nonmatching elements from the output.
#' @param incremental If \code{TRUE} and the \code{text} argument points to a
#'   file, the file is read in increasingly large blocks. This can reduce
#'   search time in large files.
#' @param x An R object.
#' @param i For indexing into an \code{"orematches"} object only, the string
#'   number.
#' @param j For indexing, the match number.
#' @param k For indexing, the group number.
#' @param lines The maximum number of lines to print. The default is zero,
#'   meaning no limit. For \code{"orematches"} objects this is split evenly
#'   between the elements printed.
#' @param context The number of characters of context to include either side
#'   of each match.
#' @param width The number of characters in each line of printed output.
#' @param ... For \code{print.orematches}, additional arguments to be passed
#'   through to \code{print.orematch}.
#' @return For \code{ore_search}, an \code{"orematch"} object, or a list of
#'   the same, each with elements
#'   \describe{
#'     \item{text}{A copy of the \code{text} element for the current match, if
#'       it was a character vector; otherwise a single string with the content
#'       retrieved from the file or connection. If the source was a binary file
#'       (from \code{ore_file(..., binary=TRUE)}) then this element will be
#'       \code{NULL}.}
#'     \item{nMatches}{The number of matches found.}
#'     \item{offsets}{The offsets (in characters) of each match.}
#'     \item{byteOffsets}{The offsets (in bytes) of each match.}
#'     \item{lengths}{The lengths (in characters) of each match.}
#'     \item{byteLengths}{The lengths (in bytes) of each match.}
#'     \item{matches}{The matched substrings.}
#'     \item{groups}{Equivalent metadata for each parenthesised subgroup in
#'       \code{regex}, in a series of matrices. If named groups are present in
#'       the regex then \code{dimnames} will be set appropriately.}
#'   }
#'   For \code{is_orematch}, a logical vector indicating whether the specified
#'   object has class \code{"orematch"}. For extraction with one index, a
#'   vector of matched substrings. For extraction with two indices, a vector
#'   or matrix of substrings corresponding to captured groups.
#' 
#' @note
#' Only named *or* unnamed groups will currently be captured, not both. If
#' there are named groups in the pattern, then unnamed groups will be ignored.
#' 
#' By default the \code{print} method uses the \code{crayon} package (if it is
#' available) to determine whether or not the R terminal supports colour.
#' Alternatively, colour printing may be forced or disabled by setting the
#' \code{"ore.colour"} (or \code{"ore.color"}) option to a logical value.
#' 
#' @examples
#' # Pick out pairs of consecutive word characters
#' match <- ore_search("(\\w)(\\w)", "This is a test", all=TRUE)
#' 
#' # Find the second matched substring ("is", from "This")
#' match[2]
#' 
#' # Find the content of the second group in the second match ("s")
#' match[2,2]
#' @seealso \code{\link{ore}} for creating regex objects; \code{\link{matches}}
#' and \code{\link{groups}} for an alternative to indexing for extracting
#' matching substrings.
#' @aliases orematch orematches ore.search ore_match ore.match
#' @export ore.search ore_search ore.match ore_match
ore_search <- ore.search <- ore_match <- ore.match <- function (regex, text, all = FALSE, start = 1L, simplify = TRUE, incremental = !all)
{
    match <- .Call(C_ore_search_all, regex, text, as.logical(all), as.integer(start), as.logical(simplify), as.logical(incremental))
    
    .Workspace$lastMatch <- match
    return (match)
}

#' @rdname ore_search
#' @aliases is.orematch
#' @export is.orematch is_orematch
is_orematch <- is.orematch <- function (x)
{
    return (inherits(x, "orematch"))
}

#' @rdname ore_search
#' @export
"[.orematch" <- function (x, j, k, ...)
{
    if (missing(k))
        return (x$matches[j])
    else
        return (x$groups$matches[j,k])
}

#' @rdname ore_search
#' @export
"[.orematches" <- function (x, i, j, k, ...)
{
    if (missing(j) && missing(k))
        return (unclass(x)[i])
    else if (missing(k))
        return (sapply(unclass(x)[i], function(match) { if (is.null(match)) NA_character_ else match[j] }, simplify="array"))
    else if (missing(j))
        return (sapply(unclass(x)[i], function(match) { if (is.null(match)) NA_character_ else match[,k,...] }, simplify="array"))
    else
        return (sapply(unclass(x)[i], function(match) { if (is.null(match)) NA_character_ else match[j,k,...] }, simplify="array"))
}

#' @rdname ore_search
#' @export
print.orematch <- function (x, lines = getOption("ore.lines",0L), context = getOption("ore.context",30L), width = getOption("width",80L), ...)
{
    # Generally x$nMatches should not be zero (because non-matches return NULL), but cover it anyway
    if (x$nMatches == 0)
        cat("<no match>\n")
    else if (is.null(x$text))
        cat(paste0("<", x$nMatches, " ", ifelse(x$nMatches==1L,"match","matches"), ">\n"))
    else
    {
        # Check the colour option; if unset, use the crayon package to check if the terminal supports colour
        if (!is.null(getOption("ore.colour")))
            usingColour <- isTRUE(getOption("ore.colour"))
        else if (!is.null(getOption("ore.color")))
            usingColour <- isTRUE(getOption("ore.color"))
        else
            usingColour <- (system.file(package="crayon") != "" && crayon::has_color())
        
        .Call(C_ore_print_match, x, context, width, lines, usingColour)
    }
    
    invisible(NULL)
}

#' @rdname ore_search
#' @export
print.orematches <- function (x, lines = getOption("ore.lines",0L), simplify = TRUE, ...)
{
    if (length(x) == 0)
        cat("<no match>\n")
    else
    {
        matching <- rep(!simplify, length(x))
        matchCount <- 0L
        for (i in seq_along(x))
        {
            if (!is.null(x[[i]]))
            {
                matching[i] <- TRUE
                matchCount <- matchCount + x[[i]]$nMatches
            }
        }
        
        cat(paste0("<", matchCount, " ", ifelse(matchCount==1L,'match','matches'), " in ", length(x), " ", ifelse(length(x)==1L,'string','strings'), ">\n"))
        
        linesPerMatch <- ifelse(lines == 0, 0, floor((lines-2) / sum(matching) - 1))
        names <- names(x)
        if (lines == 0 || linesPerMatch > 0)
        {
            cat("\n")
            for (i in which(matching))
            {
                if (!is.null(names) && names[i] != "")
                    cat(paste0("$`", names[i], "`\n"))
                else
                    cat(paste0("[[", i, "]]\n"))
                print(x[[i]], lines=linesPerMatch, ...)
            }
        }
    }
}

#' Extract matching substrings
#' 
#' These functions extract entire matches, or just subgroup matches, from
#' objects of class \code{"orematch"}. They can also be applied to lists of
#' these objects, as returned by \code{\link{ore_search}} when more than one
#' string is searched. For other objects they return \code{NA}.
#' 
#' @param object An R object. Methods are provided for generic lists and
#'   \code{"orematch"} objects. If no object is provided (i.e. the method is
#'   called with no arguments), the value of \code{\link{ore_lastmatch}} will
#'   be used as a default.
#' @param simplify For the list methods, should nonmatching elements be removed
#'   from the result?
#' @param ... Further arguments to methods.
#' @return A vector, matrix, array, or list of the same, containing full
#'   matches or subgroups. If \code{simplify} is \code{TRUE}, the result may
#'   have a \code{dropped} attribute, giving the indices of nonmatching
#'   elements.
#' @seealso \code{\link{ore_search}}
#' @export
matches <- function (object, ...)
{
    if (missing(object))
        matches(ore_lastmatch())
    else
        UseMethod("matches", object)
}

#' @rdname matches
#' @export
matches.orematches <- function (object, simplify = TRUE, ...)
{
    if (simplify)
    {
        matched <- !sapply(object, is.null)
        result <- sapply(object[matched], matches, ...)
        if (any(!matched))
            attr(result, "dropped") <- which(!matched)
        return (result)
    }
    else
        return (sapply(object, matches, ...))
}

#' @rdname matches
#' @export
matches.orematch <- function (object, ...)
{
    return (object$matches)
}

#' @rdname matches
#' @export
matches.default <- function (object, ...)
{
    return (NA_character_)
}

#' @rdname matches
#' @export
groups <- function (object, ...)
{
    if (missing(object))
        groups(ore_lastmatch())
    else
        UseMethod("groups", object)
}

#' @rdname matches
#' @export
groups.orematches <- function (object, simplify = TRUE, ...)
{
    if (simplify)
    {
        matched <- !sapply(object, is.null)
        result <- sapply(object[matched], groups, ..., simplify="array")
        if (any(!matched))
            attr(result, "dropped") <- which(!matched)
        return (result)
    }
    else
        return (sapply(object, groups, ..., simplify="array"))
}

#' @rdname matches
#' @export
groups.orematch <- function (object, ...)
{
    return (object$groups$matches)
}

#' @rdname matches
#' @export
groups.orearg <- function (object, ...)
{
    return (attr(object, "groups"))
}

#' @rdname matches
#' @export
groups.default <- function (object, ...)
{
    return (NA_character_)
}

#' Retrieve the last match
#' 
#' This function can be used to obtain the \code{"orematch"} object, or list,
#' corresponding to the last call to \code{\link{ore_search}}. This can be
#' useful after performing a search implicitly, for example with \code{\%~\%}.
#' 
#' @param simplify If \code{TRUE} and the last match was against a single
#'   string, then the \code{"orematch"} object will be returned, instead of a
#'   list with one element.
#' @return An \code{"orematch"} object or list. See \code{\link{ore_search}}
#'   for details.
#' @aliases ore.lastmatch
#' @export ore.lastmatch ore_lastmatch
ore_lastmatch <- ore.lastmatch <- function (simplify = TRUE)
{
    if (!exists("lastMatch", envir=.Workspace))
        return (NULL)
    else if (simplify && is.list(.Workspace$lastMatch) && length(.Workspace$lastMatch) == 1)
        return (.Workspace$lastMatch[[1]])
    else
        return (.Workspace$lastMatch)
}

#' Does text match a regex?
#' 
#' These functions test whether the elements of a character vector match a
#' Oniguruma regular expression. The actual match can be retrieved using
#' \code{\link{ore_lastmatch}}.
#' 
#' The \code{\%~\%} infix shorthand corresponds to \code{ore_ismatch(..., 
#' all=FALSE)}, while \code{\%~~\%} corresponds to \code{ore_ismatch(...,
#' all=TRUE)}. Either way, the first argument can be an \code{"ore"} object,
#' in which case the second is the text to search, or a character vector, in
#' which case the second argument is assumed to contain the regex. The
#' \code{\%~|\%} shorthand returns just those elements of the text vector which
#' match the regular expression.
#' 
#' @param regex A single character string or object of class \code{"ore"}.
#' @param text A character vector of strings to search.
#' @param keepNA If \code{TRUE}, \code{NA}s will be propagated from \code{text}
#'   into the return value. Otherwise, they evaluate \code{FALSE}.
#' @param ... Further arguments to \code{\link{ore_search}}.
#' @param X A character vector or \code{"ore"} object. See Details.
#' @param Y A character vector. See Details.
#' @return A logical vector, indicating whether elements of \code{text} match
#'   \code{regex}, or not.
#' 
#' @examples
#' # Test for the presence of a vowel
#' ore_ismatch("[aeiou]", c("sky","lake"))  # => c(FALSE,TRUE)
#' 
#' # The same thing, in shorter form
#' c("sky","lake") %~% "[aeiou]"
#' 
#' # Same again: the first argument must be an "ore" object this way around
#' ore("[aeiou]") %~% c("sky","lake")
#' @seealso \code{\link{ore_search}}
#' @aliases ore.ismatch
#' @export ore.ismatch ore_ismatch
ore_ismatch <- ore.ismatch <- function (regex, text, keepNA = getOption("ore.keepNA",FALSE), ...)
{
    match <- ore_search(regex, text, simplify=FALSE, ...)
    result <- !sapply(match, is.null)
    if (keepNA)
        result[is.na(text)] <- NA
    return (result)
}

#' @rdname ore_ismatch
#' @export
"%~%" <- function (X, Y)
{
    if (is_ore(X))
        return (ore_ismatch(X, Y, all=FALSE))
    else
        return (ore_ismatch(Y, X, all=FALSE))
}

#' @rdname ore_ismatch
#' @export
"%~~%" <- function (X, Y)
{
    if (is_ore(X))
        return (ore_ismatch(X, Y, all=TRUE))
    else
        return (ore_ismatch(Y, X, all=TRUE))
}

#' @rdname ore_ismatch
#' @export
"%~|%" <- function (X, Y)
{
    if (is_ore(X))
        return (Y[ore_ismatch(X,Y)])
    else
        return (X[ore_ismatch(Y,X)])
}

#' Split strings using a regex
#' 
#' This function breaks up the strings provided at regions matching a regular
#' expression, removing those regions from the result. It is analogous to the
#' \code{\link[base]{strsplit}} function in base R.
#' 
#' @inheritParams ore_search
#' @param text A vector of strings to match against.
#' @param simplify If \code{TRUE}, a character vector containing the pieces
#'   will be returned if \code{text} is of length 1. Otherwise, a list of such
#'   objects will always be returned.
#' @return A character vector or list of substrings.
#' 
#' @examples
#' ore_split("-?\\d+", "I have 2 dogs, 3 cats and 4 hamsters")
#' @seealso \code{\link{ore_search}}
#' @aliases ore.split
#' @export ore.split ore_split
ore_split <- ore.split <- function (regex, text, start = 1L, simplify = TRUE)
{
    if (!is.character(text))
        text <- as.character(text)
    
    return (.Call(C_ore_split, regex, text, as.integer(start), as.logical(simplify)))
}

#' Replace matched substrings with new text
#' 
#' These functions substitute new text into strings in regions that match a
#' regular expression. The substitutions may be simple text, may include
#' references to matched subgroups, or may be created by an R function.
#' 
#' These functions differ in how they are vectorised. \code{ore_subst}
#' vectorises over matches, and returns a vector of the same length as the
#' \code{text} argument. If multiple replacements are given then they are
#' applied to matches in turn. \code{ore_repl} vectorises over replacements,
#' replicating the elements of \code{text} as needed, and (in general)
#' returns a list the same length as \code{text}, whose elements are character
#' vectors each of the same length as \code{replacement} (or its return value,
#' if a function). Each string combines the first replacement for each match,
#' the second, and so on.
#' 
#' If \code{replacement} is a character vector, its component strings may
#' include back-references to captured substrings. \code{"\\\\0"} corresponds
#' to the whole matching substring, \code{"\\\\1"} is the first captured
#' group, and so on. Named groups may be referenced as \code{"\\\\k<name>"}.
#' 
#' If \code{replacement} is a function, then it will be passed as its first
#' argument an object of class \code{"orearg"}. This is a character vector
#' containing as its elements the matched substrings, and with an attribute
#' containing the matches for parenthesised subgroups, if there are any. A
#' \code{\link{groups}} method is available for this class, so the groups
#' attribute can be easily obtained that way. The substitution function will be
#' called once per element of \code{text} by \code{ore_subst}, and once per
#' match by \code{ore_repl}.
#' 
#' @inheritParams ore_search
#' @param text A vector of strings to match against.
#' @param replacement A character vector, or a function to be applied to the
#'   matches.
#' @param ... Further arguments to \code{replacement}, if it is a function.
#' @param simplify For \code{ore_repl}, a character vector of modified strings
#'   will be returned if this is \code{TRUE} and \code{text} is of length 1.
#'   Otherwise, a list of such objects will always be returned.
#' @return Versions of \code{text} with the substitutions made.
#' 
#' @examples
#' # Simple text substitution (produces "no dogs")
#' ore_subst("\\d+", "no", "2 dogs")
#' 
#' # Back-referenced substitution (produces "22 dogs")
#' ore_subst("(\\d+)", "\\1\\1", "2 dogs")
#' 
#' # Function-based substitution (produces "4 dogs")
#' ore_subst("\\d+", function(i) as.numeric(i)^2, "2 dogs")
#' @seealso \code{\link{ore_search}}
#' @aliases ore.subst ore.repl
#' @export ore.subst ore_subst
ore_subst <- ore.subst <- function (regex, replacement, text, ..., all = FALSE, start = 1L)
{
    if (!is.character(text))
        text <- as.character(text)
    if (!is.character(replacement))
        replacement <- match.fun(replacement)
        
    return (.Call(C_ore_substitute_all, regex, replacement, text, as.logical(all), as.integer(start), new.env(), pairlist(...)))
}

#' @rdname ore_subst
#' @export ore.repl ore_repl
ore_repl <- ore.repl <- function (regex, replacement, text, ..., all = FALSE, start = 1L, simplify = TRUE)
{
    if (!is.character(text))
        text <- as.character(text)
    if (!is.character(replacement))
        replacement <- match.fun(replacement)
    
    return (.Call(C_ore_replace_all, regex, replacement, text, as.logical(all), as.integer(start), as.logical(simplify), new.env(), pairlist(...)))
}

#' String multiplexing
#' 
#' This function maps one character vector to another, based on sequential
#' matching to a series of regular expressions. The return value corresponding
#' to each element in the source text is chosen based on the first matching
#' regex: once matched, later options are ignored.
#' 
#' @inheritParams ore
#' @param text A vector of strings to match against.
#' @param ... One or more string arguments specifying a possible return value.
#'   These are generally named with a regex, and the string is only used for a
#'   given \code{text} element if the regex matches (and no previous one
#'   matched). These strings may reference captured groups. Unnamed arguments
#'   match unconditionally, and will always be taken literally.
#' @return A character vector of the same length as \code{text}, containing the
#'   multiplexed strings. If none of the regexes matched, the corresponding
#'   element will be \code{NA}.
#' 
#' @examples
#' # Extract digits where present; otherwise return zero
#' ore_switch(c("2 dogs","no dogs"), "\\d+"="\\0", "0")
#' @seealso \code{\link{ore_subst}} for details of back-reference syntax.
#' @aliases ore.switch
#' @export ore.switch ore_switch
ore_switch <- ore.switch <- function (text, ..., options = "", encoding = getOption("ore.encoding"))
{
    if (!is.character(text))
        text <- as.character(text)
    
    return (.Call(C_ore_switch_all, text, c(...), as.character(options), as.character(encoding)))
}
