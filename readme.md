# Improved Object Menu
Egosoft thread: https://forum.egosoft.com/viewtopic.php?t=398551  
Nexusmods: https://www.nexusmods.com/xrebirth/mods/525  
Steam Workshop: http://steamcommunity.com/sharedfiles/filedetails/?id=1343434992

A full overhaul of the object details menu for improved information and readability. When this mod is installed, the new menu will open whenever the normal object menu usually would.

Improved Object Menu aims to make it quicker and nicer to get information about objects, without having to descend into other menus so much, and to make you aware of changes in the object's state (so you can "watch" the menu if you like).

To this end, the menu uses two columns which scroll independently. The categories are set up to (hopefully) make the best use of screen space in most cases. Many items convey more information than the vanilla counterpart, and use colour to make it even more informative, catching your eye on things that need attention.

Also, many items will update(!) frequently, letting you know what's going on. Cargo amounts, crew commands, boarding resistance, hull and shield, etc, are all kept up to date every few seconds.

# Usage
Basically the same as the vanilla menu. If you're not using mouse you'll need to use tab to cycle between columns, or the gamepad equivalent.

The details button (hotkey 4) is derived from the current row in the last column you tabbed to or moved your mouse over.

If you press the comm hotkey, and a crew member is selected, it will initiate comm with that crew member. Otherwise, it will comm the object as normal.

# Changes
  1.11: 2018-04-22
- Improve compatibility with other mods that change the object menu (particularly xsalvation)


  1.1: 2018-04-10
- Add `save="false"` to content.xml, can be safely removed from save games
- Change the way the vanilla object menu is replaced, improving compatibility
- Add headers to turret/weapon/missile display
- Fix bug where cargo wouldn't be displayed if it was only empty resources (e.g. immediately after station construction)
- Fix bug where returning to map from the menu wouldn't carry the history over


  1.0: 2018-04-01
- Boarding resistance also shows the Skunk's boarding strength in grey, if applicable, for comparison
- Subordinate ships have an appropriate icon like the one from the map -- if the object being viewed is a ship, you also see an icon for that next to the name
- Subordinate ships are grouped by the NPC they work for
- Reduced font size on menu title (since it is only half as wide now)
- Fixed when viewing a CV, the architect could show the operational range warning
- Fixed some unnecessary debuglog output

