FROM ruby:2.7.3

COPY library/libssl1.0.0_1.0.2n-1ubuntu5.6_amd64.deb .
RUN dpkg -i libssl1.0.0_1.0.2n-1ubuntu5.6_amd64.deb
RUN wget https://github.com/neo4j-drivers/seabolt/releases/download/v1.7.4/seabolt-1.7.4-Linux-ubuntu-16.04.deb
RUN dpkg -i seabolt-1.7.4-Linux-ubuntu-16.04.deb
# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
ENV GEM_HOME="/usr/local/bundle"
ENV PATH $GEM_HOME/bin:$GEM_HOME/gems/bin:$PATH
ENV NEO4J_URL bolt://neo4j:7687
RUN unset BUNDLE_PATH
RUN unset BUNDLE_BIN

ENV TZ=Australia/Melbourne
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


RUN gem install bundler

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN bundle install

COPY . .

RUN chmod +x /app/app.rb

CMD ["./app.rb"]