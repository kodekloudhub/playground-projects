// 1. Provision the Application User
db.createUser({
  user: "app_reader",
  pwd: "AppPassword123!",
  roles: [
    { role: "read", db: "movies" }
  ]
});
