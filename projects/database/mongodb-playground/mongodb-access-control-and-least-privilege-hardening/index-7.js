// 1. Verify you are connected as the correct user
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;

// 2. Verify you have read privileges (Should return a document)
db.tvshows.find().limit(1);

// 3. Verify write privileges are blocked (Should return an authorization error)
db.tvshows.deleteOne({ name: "HACKED: Rogue Entry" });
