import os

/// Read with: log show --last 10m --info --predicate 'subsystem == "com.szeyu.notiai"'
let appLog = Logger(subsystem: "com.szeyu.notiai", category: "app")
