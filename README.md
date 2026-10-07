# AWS Lambda Integration

Proyecto de grupo que despliega en AWS, con Terraform, un sistema para procesar imágenes. Se sube una imagen a una API, se guarda en S3 y otra función la recorta en un círculo de 40x40 píxeles con fondo transparente. El mismo código se puede desplegar en tres entornos: DEV, QA y PROD.

Nos basamos en el diagrama mermaid dado para esta tarea.

## Cómo funciona

1. El cliente envía la imagen a la API (`POST /upload`).
2. La función `upload-lambda` revisa que sea una imagen válida y la guarda en la carpeta `uploads/` del bucket de S3.
3. Cuando llega un archivo a `uploads/`, S3 manda un aviso a una cola de SQS.
4. La cola activa la función `crop-lambda`, que recorta la imagen y guarda el resultado en `processed/`.
5. Si el procesamiento de un mensaje falla 3 veces, el mensaje pasa a una cola de mensajes fallidos y una alarma de CloudWatch avisa por SNS.

De esta forma la subida y el recorte no dependen uno del otro: el cliente recibe su respuesta apenas se guarda la imagen y el recorte se hace después.

## Servicios que usamos

- **API Gateway:** recibe las imágenes en la ruta `POST /upload`.
- **upload-lambda** (Node.js 20, 256 MB, 30 s): acepta la imagen como archivo (`multipart/form-data`) o como JSON en base64. Verifica el tipo real de la imagen (jpg, png, gif o webp) y no solo la extensión.
- **crop-lambda** (Node.js 20, 512 MB, 60 s): recorta la imagen con la librería `sharp` y guarda el resultado como `<nombre>_circular.png`.
- **S3:** un bucket privado con cifrado y versioning. Los archivos de `uploads/` se borran a los 30 días y los de `processed/` a los 90.
- **SQS:** una cola principal y una cola de mensajes fallidos que guarda los mensajes 14 días.
- **VPC:** las dos funciones están en subnets privadas y llegan a S3 por un endpoint.
- **CloudWatch y SNS:** una alarma que avisa cuando hay mensajes en la cola de mensajes fallidos.

## Decisiones del grupo

Seguimos el diagrama, pero en algunos puntos decidimos hacer algo distinto. Estas son las diferencias y por qué las tomamos.

- **No creamos NAT Gateway.** Es lo más caro del diagrama (cerca de 33 dólares al mes cada uno) y nuestras funciones solo necesitan comunicarse con S3, así que usamos un endpoint de S3, que es gratis.
- **No creamos el endpoint de SQS.** Nuestras funciones nunca llaman a SQS: la cola activa a `crop-lambda` automáticamente mediante un `event source mapping`, que lo maneja el propio servicio Lambda. Por eso el endpoint no hacía falta.
- **No creamos Internet Gateway.** API Gateway no está dentro de nuestra VPC, así que no lo necesitamos.
- **Una sola función por lambda.** En el diagrama aparecen "réplicas" en la segunda zona, pero no son recursos aparte: cada función se crea una vez y AWS la reparte entre las dos subnets.
- **Security groups más cerrados.** Las dos funciones no aceptan conexiones de entrada y solo pueden salir por el puerto 443 hacia S3. Como ninguna usa SQS, quitamos esa salida. Además, el diagrama les pone nombres que empiezan con `sg-`, pero AWS no permite esos nombres, así que los llamamos `upload-lambda-sg-<entorno>` y `crop-lambda-sg-<entorno>`.
- **Política en el endpoint de S3.** Un endpoint sin política permite acceder a cualquier bucket. Siguiendo el diagrama, lo limitamos a leer y guardar archivos solo en nuestro bucket.
- **Filtro en los avisos de S3.** El aviso a la cola solo se envía para `uploads/`. Si no lo hiciéramos, los archivos que guarda `crop-lambda` en `processed/` generarían nuevos avisos y se crearía un ciclo infinito. Además, la cola solo acepta mensajes de nuestro bucket.
- **Nombre del bucket.** Usamos el formato del diagrama (`image-processor-<entorno>-images-<sufijo>`), pero con un sufijo aleatorio. Los nombres de bucket son únicos en todo AWS y cada integrante despliega en su propia cuenta, así que un sufijo fijo podía repetirse.
- **Limpieza de versiones antiguas.** Como el bucket tiene versioning, agregamos una regla para borrar las versiones viejas un día después de que un archivo expire. Si no, se acumulan y se siguen cobrando.
- **Permisos mínimos.** Cada función tiene su propio rol. `upload-lambda` solo puede guardar en `uploads/`. `crop-lambda` solo puede leer de `uploads/`, guardar en `processed/` y recibir mensajes de su cola. Los logs de cada una se limitan a su propio grupo. La única excepción es el permiso de red de `AWSLambdaVPCAccessExecutionRole`, que AWS exige para usar una VPC y no permite limitar.
- **Versiones de las librerías.** El diagrama indica `sharp 0.33`, pero `npm audit` reporta una vulnerabilidad alta en esa versión, así que usamos `sharp 0.35.5`. Por el mismo motivo usamos `uuid 11` y no la 9. Probamos el recorte con las versiones nuevas y funcionó bien.

## Estructura del repositorio

```
main.tf               provider, VPC, subnets, bucket y endpoint de S3
locals.tf             valores compartidos
s3.tf                 sufijo, cifrado, versioning, lifecycle y avisos a la cola
sqs.tf                colas y su política
vpc_endpoint.tf       política del endpoint de S3
security_groups.tf    security groups de las funciones
iam.tf                roles y permisos
lambda.tf             funciones y conexión con la cola
apigw.tf              API
monitoring.tf         alarma y SNS
outputs.tf            datos que muestra Terraform al terminar
dev.tfvars, qa.tfvars, prod.tfvars
src/upload, src/crop  código de las funciones
docs/                 diagrama del docente
```

`node_modules`, `.terraform` y los `.zip` que genera Terraform no se suben al repositorio.

## Requisitos

- Terraform 1.5 o superior
- Node.js 20 o superior
- AWS CLI con un usuario IAM que tenga permisos para crear los recursos (nosotros usamos uno con `AdministratorAccess` solo para desplegar, no la cuenta raíz)
- Región `us-east-1`

```powershell
aws configure
aws sts get-caller-identity
```

Los comandos son para PowerShell en Windows.

## Cómo desplegar

**1. Instalar las dependencias de las funciones.** Lambda funciona en Linux, así que la de `crop` se instala para Linux aunque trabajemos desde Windows:

```powershell
cd src\upload
npm ci --omit=dev
cd ..\crop
npm ci --omit=dev --os=linux --cpu=x64 --libc=glibc
cd ..\..
```

Para comprobarlo, `Get-ChildItem src\crop\node_modules\@img` debe mostrar `sharp-linux-x64`. Si falta, Terraform se detiene antes de desplegar y avisa.

**2. Desplegar un entorno.** Cada entorno usa su propio workspace de Terraform y su archivo `.tfvars`. Hay que usar el que corresponda; cambia `dev` por `qa` o `prod`:

```powershell
terraform init
terraform workspace select -or-create dev
terraform workspace show
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"
terraform output
```

En un workspace nuevo, el plan debe decir `Plan: 41 to add, 0 to change, 0 to destroy`. Si dice otra cosa, conviene revisar que el workspace y el `.tfvars` sean del mismo entorno antes de aplicar.

## Cómo probar

```powershell
$api = terraform output -raw api_url
curl.exe -i -F "file=@C:\ruta\a\foto.png" "$api"
```

En PowerShell hay que escribir `curl.exe`, porque `curl` es otro comando. Debe responder `201 Created`. Unos segundos después se puede ver el resultado:

```powershell
$bucket = terraform output -raw bucket_name
aws s3 ls "s3://$bucket/uploads/"
aws s3 ls "s3://$bucket/processed/"
```

Para ver los logs del recorte y comprobar que no hay mensajes fallidos:

```powershell
aws logs tail /aws/lambda/image-processor-dev-crop --since 15m
aws sqs get-queue-attributes --queue-url (terraform output -raw dlq_url) --attribute-names ApproximateNumberOfMessages
```

Si el archivo no es una imagen válida, la API responde `415`, y si es demasiado grande, `413`.

## Cómo destruir

Se hace un entorno a la vez, desde la misma carpeta y el mismo computador donde se desplegó, porque el estado de Terraform se guarda localmente en `terraform.tfstate.d/`. Tampoco hay que borrar la carpeta `src/` antes de destruir.

```powershell
terraform workspace select dev
terraform destroy -var-file="dev.tfvars"
terraform state list
```

Al final, `terraform state list` debe salir vacío. El bucket se vacía solo. Si aparece un error de tipo `DependencyViolation`, es porque las funciones tardan unos minutos en liberar sus interfaces de red: se espera un poco y se repite el mismo comando.

## Qué probamos

Desplegamos los tres entornos (DEV, QA y PROD) en una cuenta de AWS personal, con 41 recursos en cada uno, y en cada entorno subimos una imagen distinta. En todos obtuvimos `201 Created`, la imagen original apareció en `uploads/`, el recorte en `processed/` y la cola de mensajes fallidos quedó vacía. Después destruimos los tres entornos, comprobamos que `terraform state list` salía vacío en cada uno y revisamos en la consola que no quedara ningún recurso del proyecto. Solo permanece la VPC que AWS crea por defecto en la cuenta.

## Costos

Al no usar NAT ni el endpoint de SQS, no hay recursos con costo fijo importante. Lambda, SQS y API Gateway quedan dentro de los límites gratuitos con poco uso. Aun así, destruimos cada entorno al terminar las pruebas.

## Limitaciones

- Una función Lambda invocada desde la API admite unos 6 MB, y al enviar la imagen el tamaño aumenta un poco. Por eso, en la práctica, el máximo es de unos 4 MB, aunque el código acepta hasta los 10 MB del diagrama.
- AWS marca el runtime `nodejs20.x` como obsoleto, pero todavía nos permitió crear las funciones. Si dejara de permitirlo, habría que cambiar a `nodejs22.x` en `lambda.tf`.
- El tópico SNS no tiene correos suscritos, así que la alarma no llega a nadie. Para recibirla habría que suscribir un email.
- Los tres entornos usan los mismos rangos de red. Funciona porque cada uno tiene su propia VPC, pero no se podrían conectar entre sí.
- La API no tiene autenticación: cualquiera que conozca la URL puede subir imágenes.