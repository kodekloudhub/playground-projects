// 1. Simulate a Rogue Data Injection
db.tvshows.insertOne({ name: "HACKED: Rogue Entry", status: "Compromised" });
