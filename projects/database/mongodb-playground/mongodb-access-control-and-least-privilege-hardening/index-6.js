// 3. Test Write Access (Unauthorized)
db.tvshows.insertOne({ name: "HACKED: Second Attempt" });
