const path = require("path");
const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3 = new S3Client({});

const UPLOAD_PREFIX = process.env.UPLOAD_PREFIX;
const PROCESSED_PREFIX = process.env.PROCESSED_PREFIX;
const SIZE = Number(process.env.THUMB_SIZE);

async function leerStream(stream) {
  const partes = [];
  for await (const parte of stream) partes.push(parte);
  return Buffer.concat(partes);
}

async function procesarImagen(bucket, key) {
  // El nombre de salida siempre es el mismo para una imagen, asi que reprocesarla no duplica nada
  const nombre = path.basename(key, path.extname(key));
  const keySalida = `${PROCESSED_PREFIX}${nombre}_circular.png`;

  const objeto = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const original = await leerStream(objeto.Body);

  const radio = SIZE / 2;
  const mascara = Buffer.from(
    `<svg width="${SIZE}" height="${SIZE}" xmlns="http://www.w3.org/2000/svg"><circle cx="${radio}" cy="${radio}" r="${radio}" fill="#fff"/></svg>`
  );

  const png = await sharp(original, { limitInputPixels: 40000000 })
    .rotate()
    .resize(SIZE, SIZE, { fit: "cover" })
    .ensureAlpha()
    .composite([{ input: mascara, blend: "dest-in" }])
    .png()
    .toBuffer();

  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: keySalida,
      Body: png,
      ContentType: "image/png",
    })
  );

  console.log("imagen procesada:", key, "->", keySalida);
}

exports.handler = async (event) => {
  const fallidos = [];

  for (const registro of event.Records) {
    try {
      const cuerpo = JSON.parse(registro.body);

      // S3 manda un mensaje de prueba al crear la notificacion
      if (cuerpo.Event === "s3:TestEvent") continue;

      for (const r of cuerpo.Records || []) {
        const key = decodeURIComponent(r.s3.object.key.replace(/\+/g, " "));
        if (!key.startsWith(UPLOAD_PREFIX)) continue;
        await procesarImagen(r.s3.bucket.name, key);
      }
    } catch (err) {
      console.error("error con el mensaje", registro.messageId, err);
      fallidos.push({ itemIdentifier: registro.messageId });
    }
  }

  // Solo los mensajes que fallaron vuelven a la cola
  return { batchItemFailures: fallidos };
};