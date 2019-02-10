FROM rocker/geospatial:3.5.2

MAINTAINER Cole Brokamp cole.brokamp@gmail.com

RUN wget -q https://colebrokamp-dropbox.s3.amazonaws.com/geocoder.db -P /opt

RUN wget -q https://colebrokamp-dropbox.s3.amazonaws.com/NHGIS_US_census_tracts_5072_simplefeatures.rds -P /opt

RUN wget -q https://github.com/cole-brokamp/dep_index/raw/master/ACS_deprivation_index_by_census_tracts.rds -P /opt

# need Ruby 3 for the gems
RUN apt-get update && apt-get install -y apt-file \
  && apt-file update \
  && apt-get install software-properties-common -y \
  && apt-add-repository ppa:brightbox/ruby-ng \
  && apt-get update \
  && apt-get install ruby2.2 ruby2.2-dev -y \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN gem install sqlite3

RUN echo "options(repos = c(CRAN = 'https://cran.rstudio.com/'), prompt='R > ', download.file.method = 'libcurl')" > /.Rprofile
RUN R -e "source('https://install-github.me/cole-brokamp/CB')"
RUN R -e "install.packages(c('argparser', 'stringr'))"
RUN R -e "install.packages('jsonlite')"
RUN R -e "install.packages('sf')"

RUN mkdir /geocoder
COPY . /geocoder
RUN chmod +x /geocoder/geocode.rb
RUN chmod +x /geocoder/geocode.R

RUN cd /geocoder \
  && make install \
  && gem install Geocoder-US-2.0.4.gem


ENTRYPOINT ["/geocoder/geocode.R"]
