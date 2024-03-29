if (system.file(package="rex") != "")
{
    regex <- rex::rex(start,
        ## match the protocol -- may exist or may not
        maybe(capture(
            capture(except_some_of(":")),
            "://"
        )),
    
        ## match the path
        capture(one_or_more(not(":/"))),
    
        ## get the port
        maybe(capture(":", capture(numbers))),
    
        ## and the rest
        maybe(capture("/", anything)),
    
        end)

    url <- "http://www.clayden.org/"
    expect_equal(matches(ore_search(regex,url)), url)
}
