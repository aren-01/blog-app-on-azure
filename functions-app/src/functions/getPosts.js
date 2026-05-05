const { app } = require("@azure/functions");
const { Pool } = require("pg");



const requiredEnvVars = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"];
const missingEnvVars = requiredEnvVars.filter((key) => !process.env[key]);


const useSsl = process.env.DB_SSL !== "false";

const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 10000,
  idleTimeoutMillis: 30000,
  max: 5,
});

app.http("getPosts", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getPosts/{url?}",

  handler: async (request, context) => {
    const headers = {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };


    if (request.method === "OPTIONS") {
      return { status: 204, headers };
    }

    try {
      if (missingEnvVars.length > 0) {
        throw new Error(`Missing required environment variables: ${missingEnvVars.join(", ")}`);
      }

      context.log("DB config check:", {
        host: process.env.DB_HOST,
        port: Number(process.env.DB_PORT || 5432),
        database: process.env.DB_NAME,
        user: process.env.DB_USER,
        ssl: useSsl,
      });

      const urlParameter = request.query.get("url") || request.params.url;

      if (urlParameter) {
        const post = await getPostByUrlParameter(urlParameter);

        if (!post) {
          return {
            status: 404,
            headers,
            jsonBody: { error: "Post not found" },
          };
        }

        return {
          status: 200,
          headers,
          jsonBody: { post },
        };
      }

      const posts = await getAllPosts();

      return {
        status: 200,
        headers,
        jsonBody: { posts },
      };
    } catch (error) {
      context.error("Server error:", error);

      return {
        status: 500,
        headers,
        jsonBody: {
          error: "Failed to load posts",
          detail: error.message,
        },
      };
    }
  },
});

async function getAllPosts() {
  const result = await pool.query(`
    SELECT id, titles, url_parameter
    FROM posts
    ORDER BY id ASC
  `);

  return result.rows;
}

async function getPostByUrlParameter(urlParameter) {
  const result = await pool.query(
    `
      SELECT id, titles, url_parameter, text
      FROM posts
      WHERE url_parameter = $1
      LIMIT 1
    `,
    [urlParameter]
  );

  return result.rows[0] || null;
}
