# Apache POI runtime

These JARs provide the pinned, offline-capable Excel runtime used by Lucee. They are loaded from `Application.cfc` and were resolved from `org.apache.poi:poi-ooxml:5.4.1` plus its runtime dependencies. This avoids depending on a server-specific spreadsheet extension or a live Maven download during application startup.

Apache POI, XMLBeans, Commons IO, Commons Compress, Commons Collections, Commons Math, Log4j API and SparseBitSet use the Apache License 2.0. CurvesAPI uses the BSD 3-Clause license. Upstream license and notice files are available in each project distribution.
