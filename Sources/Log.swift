import os

/// View with: /usr/bin/log stream --predicate 'subsystem == "local.screenshotty"'
let log = Logger(subsystem: "local.screenshotty", category: "app")
