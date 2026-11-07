# Bleiben

Stay planner for Android, iOS, and web.

```
Bleiben/
  frontend/   Flutter app (mobile, iOS, web)
  backend/    Node.js API
```

## Backend

```powershell
cd backend
npm install
npm run dev
```

API: http://localhost:8000/api/health

## Frontend

Install the Flutter SDK, then:

```powershell
cd frontend
flutter create . --org com.bleiben --project-name bleiben --platforms=android,ios,web
flutter pub get
flutter run -d chrome
```

The Flutter client talks to `http://localhost:8000` on web and iOS, and `http://10.0.2.2:8000` on the Android emulator.
