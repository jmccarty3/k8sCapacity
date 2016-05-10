FROM gliderlabs/alpine

RUN apk add --update bash curl ca-certificates && rm -rf /var/cache/apk/*

ADD calculate.sh /
CMD ["/calculate.sh"]
