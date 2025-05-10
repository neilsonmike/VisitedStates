#!/usr/bin/swift

import Foundation

print("VisitedStates - Google Sheet Factoid Uploader")
print("=============================================")
print("This script provides CSV data that you can copy-paste into your Google Sheet.")
print()

// State factoids data - same as in ImportFactoids.swift
let stateFactoids = [
    // Alabama
    ["state": "Alabama", "fact": "Alabama was the first state to declare Christmas a legal holiday in 1836."],
    ["state": "Alabama", "fact": "Alabama is the only state with all major natural resources needed to make iron and steel."],
    
    // Alaska
    ["state": "Alaska", "fact": "Alaska has more coastline than all the other U.S. states combined."],
    ["state": "Alaska", "fact": "The largest salmon ever caught in Alaska weighed 97.4 pounds."],
    
    // Arizona
    ["state": "Arizona", "fact": "Arizona's Grand Canyon is considered one of the Seven Natural Wonders of the World."],
    ["state": "Arizona", "fact": "The state's saguaro cactus can live for more than 150 years."],
    
    // Arkansas
    ["state": "Arkansas", "fact": "Arkansas is the only state in the U.S. where diamonds are found naturally."],
    ["state": "Arkansas", "fact": "The World's Championship Duck Calling Contest is held annually in Stuttgart, Arkansas."],
    
    // California
    ["state": "California", "fact": "California produces over 80% of the world's almonds."],
    ["state": "California", "fact": "If California were a country, it would have the 5th largest economy in the world."],
    
    // Colorado
    ["state": "Colorado", "fact": "Colorado has the highest average elevation of any state at 6,800 feet."],
    ["state": "Colorado", "fact": "The world's largest flat-top mountain, Grand Mesa, is in Colorado."],
    
    // Connecticut
    ["state": "Connecticut", "fact": "The first telephone book ever issued contained only 50 names and was published in New Haven, Connecticut in 1878."],
    ["state": "Connecticut", "fact": "Connecticut is home to the first hamburger, Polaroid camera, color television, and helicopter."],
    
    // Delaware
    ["state": "Delaware", "fact": "Delaware was the first state to ratify the U.S. Constitution in 1787."],
    ["state": "Delaware", "fact": "Delaware has no sales tax and has lower property taxes than many states."],
    
    // Florida
    ["state": "Florida", "fact": "Florida has the longest coastline in the contiguous United States at 1,350 miles."],
    ["state": "Florida", "fact": "St. Augustine, Florida is the oldest European settlement in the United States."],
    
    // Georgia
    ["state": "Georgia", "fact": "Georgia was named after King George II of England."],
    ["state": "Georgia", "fact": "Georgia produces more peanuts than any other state."],
    
    // Hawaii
    ["state": "Hawaii", "fact": "Hawaii is the only U.S. state that grows coffee commercially."],
    ["state": "Hawaii", "fact": "Hawaii is the only state composed entirely of islands."],
    
    // Idaho
    ["state": "Idaho", "fact": "Idaho produces about one-third of all potatoes grown in the United States."],
    ["state": "Idaho", "fact": "Hells Canyon in Idaho is the deepest river gorge in North America."],
    
    // Illinois
    ["state": "Illinois", "fact": "The first McDonald's franchise opened in Des Plaines, Illinois in 1955."],
    ["state": "Illinois", "fact": "Illinois is home to the Willis Tower (formerly Sears Tower), once the tallest building in the world."],
    
    // Indiana
    ["state": "Indiana", "fact": "The Indianapolis 500 is the world's oldest major automobile race."],
    ["state": "Indiana", "fact": "In Indiana, it's illegal to attend a public event or use public transportation within four hours of eating garlic."],
    
    // Iowa
    ["state": "Iowa", "fact": "Iowa produces more corn than any other state in the U.S."],
    ["state": "Iowa", "fact": "The world's largest truck stop is located in Walcott, Iowa."],
    
    // Kansas
    ["state": "Kansas", "fact": "Kansas grows more wheat than any other state in the United States."],
    ["state": "Kansas", "fact": "Helium was discovered in natural gas in Kansas in 1905."],
    
    // Kentucky
    ["state": "Kentucky", "fact": "Kentucky is home to the world's longest cave system, Mammoth Cave."],
    ["state": "Kentucky", "fact": "Fort Knox stores about 147.3 million ounces of gold."],
    
    // Louisiana
    ["state": "Louisiana", "fact": "Louisiana is the only state with parishes instead of counties."],
    ["state": "Louisiana", "fact": "The Lake Pontchartrain Causeway is the longest bridge over water in the world."],
    
    // Maine
    ["state": "Maine", "fact": "Maine produces 99% of all wild blueberries in the United States."],
    ["state": "Maine", "fact": "Maine has 3,478 miles of coastline—more than California."],
    
    // Maryland
    ["state": "Maryland", "fact": "The first dental school in the United States was established in Baltimore in 1840."],
    ["state": "Maryland", "fact": "Maryland is home to the U.S. Naval Academy in Annapolis."],
    
    // Massachusetts
    ["state": "Massachusetts", "fact": "The first game of basketball was played in Springfield, Massachusetts in 1891."],
    ["state": "Massachusetts", "fact": "The first subway system in the United States was built in Boston in 1897."],
    
    // Michigan
    ["state": "Michigan", "fact": "Michigan has the longest freshwater coastline in the world."],
    ["state": "Michigan", "fact": "Michigan is the only state that consists of two peninsulas."],
    
    // Minnesota
    ["state": "Minnesota", "fact": "Minnesota has more than 10,000 lakes."],
    ["state": "Minnesota", "fact": "The Mall of America in Minnesota is the largest shopping mall in the United States."],
    
    // Mississippi
    ["state": "Mississippi", "fact": "Mississippi is the birthplace of blues music."],
    ["state": "Mississippi", "fact": "Coca-Cola was first bottled in Vicksburg, Mississippi in 1894."],
    
    // Missouri
    ["state": "Missouri", "fact": "The ice cream cone was invented at the 1904 World's Fair in St. Louis."],
    ["state": "Missouri", "fact": "Kansas City has more fountains than any city in the world except Rome."],
    
    // Montana
    ["state": "Montana", "fact": "Montana has the largest migratory elk herd in the nation."],
    ["state": "Montana", "fact": "Montana's Glacier National Park has more than 130 named lakes."],
    
    // Nebraska
    ["state": "Nebraska", "fact": "Nebraska is the birthplace of Kool-Aid, created in Hastings in 1927."],
    ["state": "Nebraska", "fact": "Arbor Day was founded in Nebraska City in 1872."],
    
    // Nevada
    ["state": "Nevada", "fact": "Nevada produces more gold than any other state in the U.S."],
    ["state": "Nevada", "fact": "Area 51, the highly classified Air Force facility, is located in Nevada."],
    
    // New Hampshire
    ["state": "New Hampshire", "fact": "New Hampshire was the first state to have its own state constitution."],
    ["state": "New Hampshire", "fact": "The highest wind speed ever recorded was at the Mount Washington Observatory: 231 mph."],
    
    // New Jersey
    ["state": "New Jersey", "fact": "New Jersey is home to more diners than any other state."],
    ["state": "New Jersey", "fact": "The first drive-in movie theater was opened in Camden, New Jersey in 1933."],
    
    // New Mexico
    ["state": "New Mexico", "fact": "New Mexico's Carlsbad Caverns National Park has 117 known caves."],
    ["state": "New Mexico", "fact": "The first atomic bomb was detonated at the Trinity Site in New Mexico on July 16, 1945."],
    
    // New York
    ["state": "New York", "fact": "New York was the first state to require license plates on automobiles."],
    ["state": "New York", "fact": "The first American chess tournament was held in New York in 1843."],
    
    // North Carolina
    ["state": "North Carolina", "fact": "North Carolina was the first state to establish a state university."],
    ["state": "North Carolina", "fact": "The Wright Brothers' first successful airplane flight occurred at Kitty Hawk, North Carolina."],
    
    // North Dakota
    ["state": "North Dakota", "fact": "North Dakota produces more honey than any other state."],
    ["state": "North Dakota", "fact": "The International Peace Garden straddles the border between North Dakota and Manitoba, Canada."],
    
    // Ohio
    ["state": "Ohio", "fact": "Ohio is known as the 'Birthplace of Aviation' because the Wright Brothers were from Dayton."],
    ["state": "Ohio", "fact": "The first ambulance service was established in Cincinnati in 1865."],
    
    // Oklahoma
    ["state": "Oklahoma", "fact": "Oklahoma has the highest per capita number of man-made lakes in the U.S."],
    ["state": "Oklahoma", "fact": "The first parking meter was installed in Oklahoma City in 1935."],
    
    // Oregon
    ["state": "Oregon", "fact": "Oregon has more ghost towns than any other state."],
    ["state": "Oregon", "fact": "Crater Lake in Oregon is the deepest lake in the United States."],
    
    // Pennsylvania
    ["state": "Pennsylvania", "fact": "The first baseball stadium was built in Pittsburgh in 1909."],
    ["state": "Pennsylvania", "fact": "The first daily newspaper in America was published in Philadelphia in 1784."],
    
    // Rhode Island
    ["state": "Rhode Island", "fact": "Rhode Island is the smallest state in size in the United States."],
    ["state": "Rhode Island", "fact": "Rhode Island was the first colony to declare independence from Britain."],
    
    // South Carolina
    ["state": "South Carolina", "fact": "South Carolina is known as the 'Birthplace of Sweet Tea.'"],
    ["state": "South Carolina", "fact": "The first operational golf club in America was established in Charleston in 1786."],
    
    // South Dakota
    ["state": "South Dakota", "fact": "Mount Rushmore is located in South Dakota."],
    ["state": "South Dakota", "fact": "South Dakota is home to Wind Cave, one of the longest caves in the world."],
    
    // Tennessee
    ["state": "Tennessee", "fact": "Nashville, Tennessee is known as the 'Country Music Capital of the World.'"],
    ["state": "Tennessee", "fact": "Tennessee is home to the Great Smoky Mountains, the most visited national park in the U.S."],
    
    // Texas
    ["state": "Texas", "fact": "Texas was an independent nation from 1836 to 1845."],
    ["state": "Texas", "fact": "Texas is the only state to have the flags of 6 different nations fly over it."],
    
    // Utah
    ["state": "Utah", "fact": "Utah has the greatest snow on Earth, according to its license plates."],
    ["state": "Utah", "fact": "The Great Salt Lake is the largest salt water lake in the Western Hemisphere."],
    
    // Vermont
    ["state": "Vermont", "fact": "Vermont produces more maple syrup than any other state."],
    ["state": "Vermont", "fact": "Vermont was the first state admitted to the Union after the original 13 colonies."],
    
    // Virginia
    ["state": "Virginia", "fact": "Virginia is known as the 'Mother of Presidents' because eight U.S. presidents were born there."],
    ["state": "Virginia", "fact": "The Pentagon, the world's largest office building, is located in Virginia."],
    
    // Washington
    ["state": "Washington", "fact": "Washington produces more apples than any other state."],
    ["state": "Washington", "fact": "The world's first Starbucks opened in Seattle in 1971."],
    
    // West Virginia
    ["state": "West Virginia", "fact": "West Virginia is the only state formed by seceding from a Confederate state during the Civil War."],
    ["state": "West Virginia", "fact": "The New River Gorge Bridge is one of the longest steel spans in the world."],
    
    // Wisconsin
    ["state": "Wisconsin", "fact": "Wisconsin is known as 'America's Dairyland' and is famous for cheese."],
    ["state": "Wisconsin", "fact": "The typewriter was invented in Milwaukee, Wisconsin in 1867."],
    
    // Wyoming
    ["state": "Wyoming", "fact": "Wyoming was the first state to grant women the right to vote in 1869."],
    ["state": "Wyoming", "fact": "Yellowstone National Park, the first national park in the U.S., is largely in Wyoming."]
]

// Print CSV header
print("state,fact")

// Print each factoid in CSV format
for factoid in stateFactoids {
    let state = factoid["state"] ?? ""
    let fact = factoid["fact"] ?? ""
    
    // Escape quotes and format as CSV
    let escapedFact = fact.replacingOccurrences(of: "\"", with: "\"\"")
    print("\"\(state)\",\"\(escapedFact)\"")
}

print("\nInstructions:")
print("1. Copy the CSV data above")
print("2. Open your Google Sheet")
print("3. Select cell A1")
print("4. Paste the data (Command+V)")
print("5. The data should automatically format into columns")
print("\nYour Google Sheet is now populated with factoids for all 50 states!")