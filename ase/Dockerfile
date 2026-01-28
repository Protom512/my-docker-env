
FROM registry.access.redhat.com/ubi9/ubi-minimal
EXPOSE 5000
RUN microdnf install libaio -y tar
RUN useradd -m sap
USER sap
WORKDIR /tmp
RUN curl -LO https://d1cuw2q49dpd0p.cloudfront.net/ASE16/Current/ASE_Suite.linuxamd64.tgz