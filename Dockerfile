FROM ubuntu:14.04

MAINTAINER Cole Brokamp cole.brokamp@gmail.com

RUN useradd docker \
  && mkdir /home/docker \
  && chown docker:docker /home/docker \
  && addgroup docker staff

RUN apt-get update && apt-get install -y \
  make \
  wget \
  curl \
  sqlite3 \
  libsqlite3-dev \
  flex \
  ruby-full ruby-rubyforge \
  libssl-dev \
  libssh2-1-dev \
  libcurl4-openssl-dev \
  libxml2-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

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

RUN echo "deb http://cran.rstudio.com/bin/linux/ubuntu trusty/" >> /etc/apt/sources.list \
  && apt-get update \
  && apt-get install r-base-core -y --force-yes \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN echo 'options(repos=c(CRAN = "https://cran.rstudio.com/"), download.file.method="wget")' >> /etc/R/Rprofile.site

RUN R -e "install.packages(c('tidyverse', 'stringr'))"

RUN R -e "install.packages(c('jsonlite', 'argparser'))"

RUN R -e "install.packages('remotes'); remotes::install_github('cole-brokamp/CB')"

RUN apt-get update && apt-get install -y \
  bison \
  byacc \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN add-apt-repository ppa:ubuntugis/ubuntugis-unstable

RUN apt-get update \
  && apt-get install -yqq --no-install-recommends \
  libgdal-dev \
  libgeos-dev \
  libproj-dev \
  liblwgeom-dev \
  libudunits2-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN R -e "install.packages('sf')"

RUN mkdir /root/geocoder

COPY . /root/geocoder
RUN chmod +x /root/geocoder/geocode.rb

RUN cd /root/geocoder \
  && make install \
  && gem install Geocoder-US-2.0.4.gem

RUN chmod +x /root/geocoder/geocode.R

ENTRYPOINT ["root/geocoder/geocode.R"]
