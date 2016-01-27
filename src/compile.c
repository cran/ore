#include <R.h>
#include <Rdefines.h>
#include <Rinternals.h>

#include <string.h>

#include "compile.h"

// Not strictly part of the API, but useful for case-insensitive string comparison
extern int onigenc_with_ascii_strnicmp (OnigEncoding enc, const UChar *p, const UChar *end, const UChar *sascii, int n);

// Finaliser to clear up garbage-collected "ore" objects
void ore_regex_finaliser (SEXP regex_ptr)
{
    regex_t *regex = (regex_t *) R_ExternalPtrAddr(regex_ptr);
    onig_free(regex);
    R_ClearExternalPtr(regex_ptr);
}

// Insert a group name into an R vector; used as a callback by ore_build()
int ore_store_name (const UChar *name, const UChar *name_end, int n_groups, int *group_numbers, regex_t *regex, void *arg)
{
    SEXP name_vector = (SEXP) arg;
    for (int i=0; i<n_groups; i++)
        SET_STRING_ELT(name_vector, group_numbers[i]-1, mkChar((const char *) name));
    
    return 0;
}

// Convert an R encoding value to its Oniguruma equivalent
OnigEncoding ore_r_to_onig_enc (cetype_t encoding)
{
    switch (encoding)
    {
        case CE_UTF8:
        return ONIG_ENCODING_UTF8;
        
        case CE_LATIN1:
        return ONIG_ENCODING_ISO_8859_1;
        
        default:
        return ONIG_ENCODING_ASCII;
    }
}

// Interface to onig_new(), used to create compiled regex objects
regex_t * ore_compile (const char *pattern, const char *options, cetype_t encoding, const char *syntax_name)
{
    int return_value;
    OnigErrorInfo einfo;
    regex_t *regex;
    
    // Convert R encoding to onig data type
    OnigEncoding onig_encoding = ore_r_to_onig_enc(encoding);
    
    // Parse options and convert to onig option flags
    OnigOptionType onig_options = ONIG_OPTION_NONE;
    char *option_pointer = (char *) options;
    while (*option_pointer)
    {
        switch (*option_pointer)
        {
            case 'm':
            onig_options |= ONIG_OPTION_MULTILINE;
            break;
            
            case 'i':
            onig_options |= ONIG_OPTION_IGNORECASE;
            break;
        }
        
        option_pointer++;
    }
    
    OnigSyntaxType *syntax;
    if (strncmp(syntax_name, "ruby", 4) == 0)
    {
        // Use the default (Ruby) syntax, with one adjustment: we want \d, \s and \w to work across scripts
        syntax = ONIG_SYNTAX_RUBY;
        ONIG_OPTION_OFF(syntax->options, ONIG_OPTION_ASCII_RANGE);
    }
    else if (strncmp(syntax_name, "fixed", 5) == 0)
    {
        syntax = ONIG_SYNTAX_ASIS;
    }
    else
        error("Syntax name \"%s\" is invalid\n", syntax_name);
    
    // Create the regex struct, and check for errors
    return_value = onig_new(&regex, (UChar *) pattern, (UChar *) pattern+strlen(pattern), onig_options, onig_encoding, syntax, &einfo);
    if (return_value != ONIG_NORMAL)
    {
        char message[ONIG_MAX_ERROR_MESSAGE_LEN];
        onig_error_code_to_str((UChar *) message, return_value, &einfo);
        error("Oniguruma compile: %s\n", message);
    }
    
    return regex;
}

// Retrieve a rawmatch_t object from the specified R object, which may be of class "ore" or just text
regex_t * ore_retrieve (SEXP regex_, SEXP text_)
{
    // Check the class of the regex object; if it's text this will be NULL
    SEXP class = getAttrib(regex_, R_ClassSymbol);
    if (isNull(class) || strcmp(CHAR(STRING_ELT(class,0)), "ore") != 0)
    {
        if (!isString(regex_))
            error("The specified regex must be of character mode");
        
        // Take the encoding from the search text in this case
        cetype_t encoding = CE_NATIVE;
        for (int i=0; i<length(text_); i++)
        {
            const cetype_t current_encoding = getCharCE(STRING_ELT(text_, i));
            if (current_encoding == CE_UTF8 || current_encoding == CE_LATIN1)
            {
                encoding = current_encoding;
                break;
            }
        }
        
        // Compile the regex and return
        return ore_compile(CHAR(STRING_ELT(regex_,0)), "", encoding, "ruby");
    }
    else
        return (regex_t *) R_ExternalPtrAddr(getAttrib(regex_, install(".compiled")));
}

// Create a pattern string by concatenating the elements of the supplied vector, parenthesising named elements
char * ore_build_pattern (SEXP pattern_)
{
    const int pattern_parts = length(pattern_);
    if (pattern_parts < 1)
        error("Pattern vector is empty");
    
    // Count up the full length of the string
    size_t pattern_len = 0;
    for (int i=0; i<pattern_parts; i++)
        pattern_len += strlen(CHAR(STRING_ELT(pattern_, i)));
    
    // Allocate memory for all parts, plus surrounding parentheses
    char *pattern = R_alloc(2*pattern_parts + pattern_len, 1);
    
    // Retrieve element names
    SEXP names = getAttrib(pattern_, R_NamesSymbol);
    char *ptr = pattern;
    for (int i=0; i<pattern_parts; i++)
    {
        const char *current_string = CHAR(STRING_ELT(pattern_, i));
        size_t current_len = strlen(current_string);
        Rboolean name_present = (!isNull(names) && strcmp(CHAR(STRING_ELT(names,i)), "") != 0);
        
        if (name_present)
            strncpy(ptr++, "(", 1);
        
        // Copy in the element
        strncpy(ptr, current_string, current_len);
        ptr += current_len;
        
        if (name_present)
            strncpy(ptr++, ")", 1);
    }
    
    // Nul-terminate the string
    *ptr = '\0';
    
    return pattern;
}

// R wrapper for ore_compile(): builds the regex and creates an R "ore" object
SEXP ore_build (SEXP pattern_, SEXP options_, SEXP encoding_name_, SEXP syntax_name_)
{
    regex_t *regex;
    int n_groups, return_value;
    SEXP result, regex_ptr;
    
    // Obtain pointers to content
    const char *pattern = (const char *) ore_build_pattern(pattern_);
    const char *options = CHAR(STRING_ELT(options_, 0));
    const UChar *encoding_name = (const UChar *) CHAR(STRING_ELT(encoding_name_, 0));
    const char *syntax_name = CHAR(STRING_ELT(syntax_name_, 0));
    
    cetype_t encoding;
    if (onigenc_with_ascii_strnicmp(ONIG_ENCODING_ASCII, encoding_name, encoding_name + 4, (const UChar *) "auto", 4) == 0)
        encoding = getCharCE(STRING_ELT(pattern_, 0));
    else if (onigenc_with_ascii_strnicmp(ONIG_ENCODING_ASCII, encoding_name, encoding_name + 4, (const UChar *) "utf8", 4) == 0)
        encoding = CE_UTF8;
    else if (onigenc_with_ascii_strnicmp(ONIG_ENCODING_ASCII, encoding_name, encoding_name + 5, (const UChar *) "utf-8", 5) == 0)
        encoding = CE_UTF8;
    else if (onigenc_with_ascii_strnicmp(ONIG_ENCODING_ASCII, encoding_name, encoding_name + 6, (const UChar *) "latin1", 6) == 0)
        encoding = CE_LATIN1;
    else
        encoding = CE_NATIVE;
        
    regex = ore_compile(pattern, options, encoding, syntax_name);
    
    // Get and store number of captured groups
    n_groups = onig_number_of_captures(regex);
    
    PROTECT(result = mkString(pattern));
    
    // Create R external pointer to compiled regex
    PROTECT(regex_ptr = R_MakeExternalPtr(regex, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(regex_ptr, &ore_regex_finaliser, FALSE);
    setAttrib(result, install(".compiled"), regex_ptr);
    
    setAttrib(result, install("options"), ScalarString(STRING_ELT(options_, 0)));
    setAttrib(result, install("syntax"), ScalarString(STRING_ELT(syntax_name_, 0)));
    
    switch (encoding)
    {
        case CE_UTF8:
        setAttrib(result, install("encoding"), mkString("UTF-8"));
        break;
        
        case CE_LATIN1:
        setAttrib(result, install("encoding"), mkString("latin1"));
        break;
        
        default:
        setAttrib(result, install("encoding"), mkString("unknown"));
        break;
    }
    
    setAttrib(result, install("nGroups"), ScalarInteger(n_groups));
    
    // Obtain group names, if available
    if (n_groups > 0)
    {
        SEXP names;
        Rboolean named = FALSE;
        
        PROTECT(names = NEW_CHARACTER(n_groups));
        for (int i=0; i<n_groups; i++)
            SET_STRING_ELT(names, i, NA_STRING);
        
        return_value = onig_foreach_name(regex, &ore_store_name, names);
        
        for (int i=0; i<n_groups; i++)
        {
            if (STRING_ELT(names, i) != NA_STRING)
            {
                named = TRUE;
                break;
            }
        }
        
        if (named)
            setAttrib(result, install("groupNames"), names);
        
        UNPROTECT(1);
    }
    
    setAttrib(result, R_ClassSymbol, mkString("ore"));
    
    UNPROTECT(2);
    return result;
}