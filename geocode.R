#!/usr/bin/Rscript

suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(stringr))
# library(CB)

setwd('/tmp')

suppressPackageStartupMessages(library(argparser))
p <- arg_parser('offline geocoding, returns the input file with geocodes appended')
p <- add_argument(p,'file_name',help='name of input csv file with a column named "address"')
args <- parse_args(p)

# import data

message('\n', 'reading in address file: ', args$file_name, '...\n')

d <- read_csv(args$file_name)

# must contain character column called address
if (! 'address' %in% names(d)) stop('no column called address found in the input file', call. = FALSE)

message('\n', 'removing excess whitespace', '...\n')
d <- d %>% mutate(address = str_replace_all(address, '[[:blank:]]', ' '))

message('removing non-alphanumeric characters', '...\n')
d <- d %>%
    mutate(address = str_replace_all(address, fixed('\\'), ''),
           address = str_replace_all(address, fixed('"'), ''),
           address = str_replace_all(address, '[^[:alnum:] ]', ''))

message('flagging known Cincinnati foster & institutional addresses, "foreign", "verify", "unknown"', 'and missing addresses', '...\n')
foster_char_strings <- c('Ronald McDonald House',
                         '350 Erkenbrecher Ave',
                         '350 Erkenbrecher Avenue',
                         '350 Erkenbrecher Av',
                         '222 East Central Parkway',
                         '222 East Central Pkwy',
                         '222 East Central Pky',
                         '222 Central Parkway',
                         '222 Central Pkwy',
                         '222 Central Pky',
                         '3333 Burnet Ave',
                         '3333 Burnet Avenue',
                         '3333 Burnet Av',
                         'verify',
                         'foreign',
                         'foreign country',
                         'unknown')
d <- d %>%
    mutate(bad_address = map(address, ~ str_detect(.x, coll(foster_char_strings, ignore_case=TRUE)))) %>%
    mutate(bad_address = map_lgl(bad_address, any))
d[is.na(d$address), 'bad_address'] <- TRUE

message('flagging PO boxes', '...\n')
no_no_regex_strings <- c('(10722\\sWYS)',
                         '\\bP(OST)*\\.*\\s*[O|0](FFICE)*\\.*\\sB[O|0]X',
                         '(3333\\s*BURNETT*\\s*A.*452[12]9)')
d <- d %>%
    mutate(PO = map(address, ~ str_detect(.x, regex(no_no_regex_strings, ignore_case=TRUE)))) %>%
    mutate(PO = map_lgl(PO, any))

d_excluded_for_address <- d %>% filter(bad_address | PO)
d_for_geocoding <- d %>% filter(!bad_address & !PO)

geocode <- function(addr_string) {
    stopifnot(class(addr_string)=='character')
    out <- system2('ruby',
                   args = c('/root/geocoder/geocode.rb', shQuote(addr_string)),
                   stderr=TRUE,stdout=TRUE) %>%
        jsonlite::fromJSON()
    # if geocoder returns nothing then system will return empty list
    if (length(out) == 0) out <- tibble(lat = NA, lon = NA, score = NA, precision = NA)
    out
    }

message('now geocoding', '...\n')

d_for_geocoding$geocodes <- CB::mappp(d_for_geocoding$address,
                                      geocode,
                                      parallel = TRUE,
                                      cache = TRUE,
                                      cache.name = 'geocoding_cache')

message('geocoding complete; now filtering to precise geocodes', '...\n')

# extract results, if a tie then take first returned result
d_for_geocoding <- d_for_geocoding %>%
    mutate(lat = map(geocodes, 'lat') %>% map_dbl(1),
           lon = map(geocodes, 'lon') %>% map_dbl(1),
           score = map(geocodes, 'score') %>% map_dbl(1),
           precision = map(geocodes, 'precision') %>% map_chr(1)) %>%
    select(-geocodes)

d_for_geocoding <- d_for_geocoding %>%
    mutate(precise_geocode = {{!is.na(score)} & score > 0.5} & precision %in% c('range', 'street'))

# set imprecise geocoding results to be missing
d_for_geocoding[! d_for_geocoding$precise_geocode, 'lat'] <- NA
d_for_geocoding[! d_for_geocoding$precise_geocode, 'lon'] <- NA

d_geocoded_precise <- filter(d_for_geocoding, precise_geocode)
d_geocoded_imprecise <- filter(d_for_geocoding, ! precise_geocode)

message('\n\n', 'joining to 2010 TIGER/Line+ census tracts (modified by NHGIS to remove costal water areas) using EPSG:5072 projection', '...\n')

# make projected object for tract overlay (save original coords b/c rounding / transformations)
suppressPackageStartupMessages(library(sf))

d_geocoded_precise <- d_geocoded_precise %>%
        mutate(geocoded_lat = lat,
               geocoded_lon = lon) %>%
    st_as_sf(coords = c('lon', 'lat'), crs = 4326) %>%
    st_transform(5072)

# this file was created by downloading the 2010 tract shapefile from NHGIS and with sf in R:
# read in shapefile; reproject to epsg:5072; take only GEOID10 column and call it fips_tract_id
tract_shps <- readRDS('/opt/NHGIS_US_census_tracts_5072_simplefeatures.rds')

d_geocoded_precise_tract <- st_join(d_geocoded_precise, tract_shps)

# remove duplicated tracts (either tied overlays or duplicated addresses within ID)
duplicated_tracts <- d_geocoded_precise_tract %>%
    select(-fips_tract_id) %>%
    duplicated()
d_geocoded_precise_tract <- filter(d_geocoded_precise_tract, ! duplicated_tracts)

# add back in original geocoded lat/lon coords
d_geocoded_precise_tract <- d_geocoded_precise_tract %>%
    st_set_geometry(NULL) %>%
    rename(lat = geocoded_lat,
           lon = geocoded_lon) %>%
    as_tibble()

message('adding tract-level deprivation index (https://github.com/cole-brokamp/dep_index)', '...\n')

d_dep <- readRDS('/opt/ACS_deprivation_index_by_census_tracts.rds') %>% rename(fips_tract_id = census_tract_fips)

suppressWarnings(
d_geocoded_precise_tract_dep <- left_join(d_geocoded_precise_tract, d_dep, by='fips_tract_id')
)

d_out <- bind_rows(d_excluded_for_address, d_geocoded_imprecise, d_geocoded_precise_tract_dep)

out_file_name <- paste0(gsub('.csv', '', args$file_name, fixed=TRUE), '_geocoded.csv')
write_csv(d_out, out_file_name)
message('FINISHED! output written to ', out_file_name)
