# Pin npm packages by running ./bin/importmap

pin "application"
pin "@rails/actioncable", to: "@rails--actioncable.js" # @8.1.300
pin "three" # 0.160.1 single-file build (vendored from jsdelivr)
pin_all_from "app/javascript/game", under: "game"
