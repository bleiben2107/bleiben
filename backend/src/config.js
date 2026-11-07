export const config = {
  port: Number(process.env.PORT || 8000),
  appName: process.env.APP_NAME || "Bleiben",
  secretKey: process.env.SECRET_KEY || "bleiben-dev-secret-change-me",
  tokenExpireMinutes: Number(process.env.ACCESS_TOKEN_EXPIRE_MINUTES || 60 * 24 * 7),
  dataFile: process.env.DATA_FILE || "./data/bleiben.json",
  corsOrigins: process.env.CORS_ORIGINS || "*",
};

export function corsOriginList() {
  if (config.corsOrigins.trim() === "*") {
    return "*";
  }
  return config.corsOrigins
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}
