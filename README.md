fatcat
======

File Analysis Through Copious Amounts of Tools - a malware analysis framework

3 components - each component can be using independantly or together

1. File extractions     - based on including/exluding file/mime/ext types - built for the the Solera device
2. File distribution    - based on subscription of file analysis agents using file/mime/ext types
3. File analysis agents - multiple agents eat files and log results for ingestion to alerting system ie SEIM
