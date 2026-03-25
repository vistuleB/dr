import { defineConfig, loadEnv } from "vite";
import { exec } from "child_process";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  const courseFolder = env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = Number(env.PORT) || 3003;

  return {
    root: rootPath,
    plugins: [
      {
        name: "mathjax-injector",
        transformIndexHtml(html) {
          const version = (env.MATHJAX_VERSION || "3").trim();
          const offline = (env.OFFLINE_MODE || "false").toLowerCase().trim();

          const version_offline = `${version}-${offline}`;

          const mathjax_url = () => {
            switch (version_offline) {
              case "3-true":
                return "/mathjax3/tex-svg.js";
              case "4-true":
                console.warn(
                  "Currently MATHJAX_VERSION 4 OFFLINE_MODE is not supported. Using CDN version instead.",
                );
                return "https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js";
              case "3-false":
                return "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js";
              case "4-false":
                return "https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js";
              default:
                console.warn(
                  `[MathJax Plugin] Cannot parse: VERSION=${version}, OFFLINE=${offline}`,
                );
                console.warn("Defaulting to CDN mathjax version 3");
                return "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js";
            }
          };

          const tag = `<script type="text/javascript" id="MathJax-script" src="${mathjax_url()}"></script>`;
          return html.replace("</head>", `${tag}\n</head>`);
        },
      },
    ],
    server: {
      port: serverPort,
      host: "0.0.0.0",
      cors: true,
    },
  };
});
