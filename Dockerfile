FROM ruby:2.6.3

WORKDIR /app

ADD . /app
RUN bundle install --path=vendor/bundle

CMD ["bundle", "exec", "ruby", "app.rb"]
