FROM registry.access.redhat.com/ubi9/ubi:latest as base
RUN dnf install -y shadow-utils  tar gzip && useradd sybase && mkdir /opt/sap

FROM   base as installer
WORKDIR /tmp
RUN set -x \
 && curl -OLS https://d1cuw2q49dpd0p.cloudfront.net/ASE16/Current/ASE_Suite.linuxamd64.tgz \
 && mkdir -p /opt/tmp/ \
 && tar xfz ASE_Suite.linuxamd64.tgz -C /opt/tmp/ \
 && rm -rf ASE_Suite.linuxamd64.tgz


ADD sap-response.txt /tmp/
RUN /opt/tmp/setup.bin -i silent \
    -f /tmp/sap-response.txt \
    -DAGREE_TO_SAP_LICENSE=true \
    -DRUN_SILENT=true
RUN touch /opt/sap/interfaces
RUN rm -rf /opt/sap/ASE-16_1/bin/diagserver  /opt/sap/sybuninstall /opt/sap/ASE-16_1/sample/ /opt/sap/ASE-16_1/symlib/ /opt/sap/ASE*/**/*upgrade
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest as base
ENV LANG=ja_JP.utf8
#USER sybase
WORKDIR /opt/sap
RUN microdnf install -y libaio pam

COPY --chown=sybase --from=installer /opt/sap/SYBASE.sh /opt/sap/
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/bin /opt/sap/ASE-16_1/bin
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/locales /opt/sap/ASE-16_1/locales
COPY --chown=sybase --from=installer /opt/sap/ASE-16_1/scripts /opt/sap/ASE-16_1/scripts
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/lib3p64 /opt/sap/OCS-16_1/lib3p64
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/bin /opt/sap/OCS-16_1/bin
COPY --chown=sybase --from=installer /opt/sap/OCS-16_1/lib /opt/sap/OCS-16_1/lib
COPY --chown=sybase --from=installer /opt/sap/charsets /opt/sap/charsets
COPY --chown=sybase --from=installer /opt/sap/locales /opt/sap/locales
COPY --chown=sybase --from=installer /opt/sap/config /opt/sap/config
COPY --chown=sybase --from=installer /opt/sap/collate /opt/sap/collate
ADD  entrypoint.sh /opt/sap/
CMD ["/opt/sap/entrypoint.sh"]
