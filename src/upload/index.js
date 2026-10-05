const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const Busboy = require("busboy");
const { v4: uuidv4 } = require("uuid");

const s3 = new S3Client({});

const BUCKET = process.env.S3_BUCKET;
const PREFIX = process.env.UPLOAD_PREFIX;
const MAX_BYTES = Number(process.env.MAX_UPLOAD_BYTES);
const ALLOWED = process.env.ALLOWED_EXTENSIONS.split(",");

const MIME = {
  jpg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
};

function respuesta(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

// Revisa los primeros bytes del archivo para saber su tipo real
function detectarTipo(buf) {
  if (buf.length < 12) return null;
  if (buf[0] === 0x89 && buf.toString("ascii", 1, 4) === "PNG") return "png";
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "jpg";
  if (buf.toString("ascii", 0, 4) === "GIF8") return "gif";
  if (buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") return "webp";
  return null;
}

function limpiarNombre(nombre) {
  const base = (nombre || "image").replace(/\.[^.]+$/, "");
  return base.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 60) || "image";
}

function leerMultipart(event) {
  return new Promise((resolve, reject) => {
    const raw = Buffer.from(event.body || "", event.isBase64Encoded ? "base64" : "utf8");
    const bb = Busboy({
      headers: { "content-type": event.headers["content-type"] },
      limits: { files: 1, fileSize: MAX_BYTES },
    });

    let archivo = null;
    let excedido = false;

    bb.on("file", (campo, stream, info) => {
      const partes = [];
      stream.on("data", (parte) => partes.push(parte));
      stream.on("limit", () => {
        excedido = true;
      });
      stream.on("end", () => {
        archivo = { nombre: info.filename, buffer: Buffer.concat(partes) };
      });
    });

    bb.on("error", reject);
    bb.on("close", () => {
      if (excedido) return reject(Object.assign(new Error("muy grande"), { status: 413 }));
      resolve(archivo);
    });

    bb.end(raw);
  });
}

function leerJson(event) {
  const texto = event.isBase64Encoded
    ? Buffer.from(event.body, "base64").toString("utf8")
    : event.body;
  const datos = JSON.parse(texto || "{}");
  if (!datos.content) return null;
  const base64 = String(datos.content).replace(/^data:[^;]+;base64,/, "");
  return { nombre: datos.filename, buffer: Buffer.from(base64, "base64") };
}

exports.handler = async (event) => {
  try {
    const tipo = (event.headers["content-type"] || "").toLowerCase();
    let archivo;

    if (tipo.startsWith("multipart/form-data")) {
      archivo = await leerMultipart(event);
    } else if (tipo.startsWith("application/json")) {
      archivo = leerJson(event);
    } else {
      return respuesta(415, { error: "Usa multipart/form-data o application/json con base64" });
    }

    if (!archivo || archivo.buffer.length === 0) {
      return respuesta(400, { error: "No se recibio ningun archivo" });
    }
    if (archivo.buffer.length > MAX_BYTES) {
      return respuesta(413, { error: "El archivo supera el tamano maximo" });
    }

    const ext = detectarTipo(archivo.buffer);
    if (!ext || !ALLOWED.includes(ext)) {
      return respuesta(415, { error: "Tipo de imagen no permitido" });
    }

    const id = uuidv4();
    const key = `${PREFIX}${id}_${limpiarNombre(archivo.nombre)}.${ext}`;

    await s3.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: key,
        Body: archivo.buffer,
        ContentType: MIME[ext],
      })
    );

    console.log("imagen subida:", key);
    return respuesta(201, { id, bucket: BUCKET, key, size: archivo.buffer.length });
  } catch (err) {
    if (err.status === 413) return respuesta(413, { error: "El archivo supera el tamano maximo" });
    if (err instanceof SyntaxError) return respuesta(400, { error: "JSON invalido" });
    console.error("error en upload:", err);
    return respuesta(500, { error: "Error interno" });
  }
};