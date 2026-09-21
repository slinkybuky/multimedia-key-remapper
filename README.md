# multimedia-key-remapper

this script is built to solve the issue all Chromebook Linux users have: the top row multimedia keys don't work on Linux how they do on ChromeOS! this script installs keyd and generates a keyd config to remap the top row keys to their multimedia functions while making them still send the function key values when the meta layer is enabled.

i built this script because all the other ones i could find frankly sucked, so i thought, "why not make one myself?" and so i did. rather than changing the actual Linux files, it just translates the keys in real time, meaning it can even dynamically refresh with new settings without requiring a reboot! plus, this script is even more robust, auto-detecting the built-in Chromebook keyboard (for some reason from what i can find most of the time it's just named at Translated Set 2 Keyboard, not that i'm complaining cuz it made my life easier), making the config only apply to the built-in keyboard (so external keyboards are unaffected), and allowing you to individually choose the remapping functions if you so desire.

# contributing

if you want something to be added, feel free to drop an issue or a pull request!
