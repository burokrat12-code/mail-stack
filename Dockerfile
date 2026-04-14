FROM alpine:3.20

ENV TZ=Europe/Moscow

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-lmtpd \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates \
    tzdata

# ===== базовые директории =====
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private

# ===== users/groups (ВАЖНО для стабильности в Alpine) =====
RUN addgroup -S mail || true && adduser -S mail -G mail || true \
 && addgroup -S postfix || true && adduser -S postfix -G postfix || true \
 && addgroup -S dovecot || true && adduser -S dovecot -G dovecot || true

# ===== fix permissions =====
RUN chown -R postfix:postfix /var/spool/postfix || true

# ===== supervisor =====
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
