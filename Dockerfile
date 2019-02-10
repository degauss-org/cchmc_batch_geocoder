FROM rocker/geospatial:3.5.2

MAINTAINER Cole Brokamp cole.brokamp@gmail.com

RUN wget -q https://colebrokamp-dropbox.s3.amazonaws.com/geocoder.db -P $HOME

RUN wget -q https://colebrokamp-dropbox.s3.amazonaws.com/NHGIS_US_census_tracts_5072_simplefeatures.rds -P $HOME

RUN wget -q https://github.com/cole-brokamp/dep_index/raw/master/ACS_deprivation_index_by_census_tracts.rds -P $HOME

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  ruby \
  ruby-dev \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN gem install sqlite3

RUN echo "options(repos = c(CRAN = 'https://cran.rstudio.com/'), download.file.method = 'libcurl')" > /.Rprofile
RUN R -e "source('https://install-github.me/cole-brokamp/CB')"
RUN R -e "install.packages(c('argparser', 'stringr', 'jsonlite'))"

RUN mkdir $HOME/geocoder
COPY . $HOME/geocoder
# RUN chmod +x /geocoder/geocode.rb
# RUN chmod +x /geocoder/geocode.R

RUN cd $HOME/geocoder \
  && make install \
  && gem install Geocoder-US-2.0.4.gem

ENTRYPOINT ["$HOME/geocoder/geocode.R"]
