# Dockerfile: waifufetch bash 3.2 compatibility test
# Build:   docker build -t waifu-bash32 -f tests/test-bash32.Dockerfile .
# Run:     docker run -it --rm waifu-bash32

FROM alpine:3.21
RUN apk add --no-cache curl gcc musl-dev make ncurses-dev xz sed
COPY tests/patch-bash32.sh /tmp/patch-bash32.sh
RUN curl -sL https://ftp.gnu.org/gnu/bash/bash-3.2.tar.gz | tar xz -C / \
    && /bin/sh /tmp/patch-bash32.sh \
    && cd /bash-3.2 \
    && ./configure --prefix=/usr/local \
       --disable-nls --without-bash-malloc \
       --with-installed-readline=no \
       CFLAGS="-g -O2 -DUSE_POSIX_GLOB_LIBRARY -fcommon -std=gnu89" 2>&1 \
    && touch lib/intl/libintl.h \
    && make CFLAGS="-g -O2 -DUSE_POSIX_GLOB_LIBRARY -fcommon -w -std=gnu89" 2>&1 \
    && make install 2>&1 \
    && rm -rf /tmp/* /bash-3.2
RUN apk add --no-cache chafa imagemagick jq sed
RUN ln -sf /usr/local/bin/bash /usr/local/bin/bash32
WORKDIR /waifufetch
COPY . /waifufetch/
CMD /waifufetch/tests/run-bash32-test.sh
