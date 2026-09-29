# Guía de Desarrollo de Código — Virtualization Lab (Spring Boot)

Esta guía explica **cómo se construyó cada pieza de código** de este repositorio: qué hace cada
línea, por qué se escribió así, y qué conceptos hay detrás. No es un manual de despliegue (eso
está en `DEPLOYMENT-STEPS.md`, en esta misma carpeta) — es un manual de **desarrollo**, pensado
para que cualquiera pueda entender el código como si lo estuviera escribiendo desde cero.

---

## 1. `pom.xml` — la configuración del proyecto Maven

Maven necesita un archivo `pom.xml` (Project Object Model) para saber qué construir, con qué
dependencias, y cómo empaquetarlo. Vamos bloque por bloque:

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.1</version>
</parent>
```

Esto declara un **POM padre**. No es una dependencia normal: es una plantilla de configuración que
Spring Boot provee para que no tengamos que fijar manualmente la versión de cada librería que
usemos (Jackson, Tomcat, SLF4J, etc.). El padre define un "Bill of Materials" (BOM) con versiones
que ya se probaron juntas y son compatibles entre sí. Por eso más abajo declaramos la dependencia
`spring-boot-starter-web` **sin** especificar su versión — el padre la resuelve automáticamente.

```xml
<groupId>co.edu.escuelaing</groupId>
<artifactId>virtualization-lab</artifactId>
<version>1.0.0</version>
```

Esto identifica **nuestro propio proyecto**: `groupId` (organización/paquete raíz),
`artifactId` (nombre del proyecto, que además se usa para nombrar el `.jar` final:
`virtualization-lab-1.0.0.jar`), y `version`.

```xml
<properties>
    <java.version>21</java.version>
</properties>
```

Le dice a Maven (y, por herencia, al plugin del compilador que trae el padre de Spring Boot) que
compile el código como Java 21 — esto habilita sintaxis moderna (por ejemplo, el `switch`
expresivo, records, etc., aunque en este proyecto no los usamos porque el código es simple).

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
</dependencies>
```

Este *starter* es un paquete que agrupa, con un solo `<dependency>`, todo lo necesario para hacer
una aplicación web REST: Spring MVC (el framework que interpreta `@RestController`,
`@GetMapping`, etc.), Jackson (para convertir objetos Java a JSON automáticamente, aunque en
nuestros endpoints devolvemos `String` plano), y **Tomcat embebido** — un servidor HTTP completo
que se arranca *dentro* del propio proceso Java, sin necesidad de instalar nada externo.

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
    </plugins>
</build>
```

Sin este plugin, `mvn package` generaría un `.jar` "normal" que **no** incluye las dependencias
(un JAR "thin", que fallaría al ejecutarse con `java -jar` porque le faltarían las clases de
Spring). Este plugin reempaqueta el JAR como un **"fat/über jar"**: mete adentro tanto nuestras
clases como las de todas las dependencias (Spring, Tomcat, etc.), y configura el manifiesto para
que `java -jar target/virtualization-lab-1.0.0.jar` funcione de forma completamente autónoma.

---

## 2. `RestServiceApplication.java` — el punto de entrada

```java
package co.edu.escuelaing;

import java.util.Map;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class RestServiceApplication {
    public static void main(String[] args) {
        SpringApplication aplication = new SpringApplication(RestServiceApplication.class);

        aplication.setDefaultProperties(
            Map.of("server.port", System.getenv().getOrDefault("PORT", "9000")));

        aplication.run(args);
    }
}
```

**Línea por línea:**

- `import ... SpringBootApplication` y `@SpringBootApplication` (encima de la clase): esta
  anotación es en realidad un *atajo* que combina tres anotaciones en una:
  - `@Configuration`: marca la clase como fuente de configuración de Spring (podríamos definir
    `@Bean`s aquí si quisiéramos).
  - `@EnableAutoConfiguration`: le dice a Spring Boot "detecta qué hay en el classpath y
    configúralo tú solo" — por ejemplo, como detecta `spring-boot-starter-web`, automáticamente
    levanta un Tomcat embebido y configura Spring MVC, sin que nosotros escribamos ni una línea
    de configuración XML o Java para eso.
  - `@ComponentScan`: le dice a Spring que busque, en el mismo paquete (`co.edu.escuelaing`) y
    subpaquetes, clases anotadas con `@RestController`, `@Service`, `@Component`, etc., y las
    registre automáticamente. Por eso `HelloRestController` no necesita mencionarse en ningún
    lado explícitamente: Spring lo encuentra solo porque vive en el mismo paquete.

- `public static void main(String[] args)`: el punto de entrada estándar de cualquier programa
  Java. Cuando ejecutamos `java -jar app.jar`, la JVM busca este método y lo ejecuta.

- `SpringApplication aplication = new SpringApplication(RestServiceApplication.class);`
  Crea manualmente una instancia de `SpringApplication` en lugar de usar el atajo estático
  `SpringApplication.run(RestServiceApplication.class, args)` que se ve en la mayoría de
  tutoriales. Se hace así **a propósito**, porque necesitamos una referencia al objeto
  `aplication` para poder llamar a `setDefaultProperties(...)` antes de arrancar — el atajo
  estático no nos deja inyectar propiedades por código antes del arranque.

- `aplication.setDefaultProperties(Map.of("server.port", System.getenv().getOrDefault("PORT", "9000")));`
  Esta es la línea clave de todo el ejercicio de "configuración por variable de entorno":
  - `System.getenv()` devuelve un `Map<String, String>` con **todas** las variables de entorno
    del sistema operativo en el que corre el proceso.
  - `.getOrDefault("PORT", "9000")` busca la clave `"PORT"` en ese mapa; si existe, usa su valor;
    si no existe (por ejemplo, cuando corremos localmente sin definirla), usa `"9000"` como
    respaldo.
  - `Map.of("server.port", valorDelPuerto)` crea un mapa inmutable de una sola entrada, usando
    el nombre de propiedad `"server.port"` — que es exactamente la propiedad que Spring Boot lee
    internamente para decidir en qué puerto debe escuchar el Tomcat embebido.
  - `setDefaultProperties(...)` registra ese mapa como **propiedades por defecto**: si alguien
    define `server.port` de otra forma (por ejemplo, en un `application.properties`, o con
    `-Dserver.port=...` al arrancar), esa otra fuente tiene prioridad; nuestro valor solo se usa
    si nadie más lo especificó. Esto es justo el comportamiento que queremos: "usa el puerto de
    `PORT` si existe, si no, 9000por defecto, pero sin cerrarle la puerta a otras formas de
    configurarlo".

- `aplication.run(args);` — este es el que realmente arranca todo: crea el contexto de Spring,
  ejecuta el `@ComponentScan`, levanta el Tomcat embebido en el puerto resuelto, y deja el hilo
  principal corriendo (bloqueado) mientras el servidor está vivo.

> **Nota sobre el nombre de la variable `aplication`:** está escrito así (con una sola "p") en el
> código real del repositorio. Es un identificador local sin ningún significado especial más allá
> de nombrar la instancia — no afecta el comportamiento del programa, solo hay que ser consistente
> y usar el mismo nombre en las tres líneas donde se referencia.

---

## 3. `HelloRestController.java` — el controlador REST

```java
package co.edu.escuelaing;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloRestController {

    @GetMapping("/greeting")
    public String greeting(
            @RequestParam(value = "name", defaultValue = "World") String name) {
        return "Hello, " + name;
    }
}
```

- `@RestController`: es la combinación de `@Controller` (le dice a Spring "esta clase maneja
  peticiones HTTP") + `@ResponseBody` (le dice "lo que devuelvan los métodos no es el nombre de
  una vista/plantilla HTML — es directamente el cuerpo de la respuesta"). Por eso el método
  `greeting` puede simplemente `return "Hello, " + name;` y ese texto se escribe tal cual en el
  cuerpo de la respuesta HTTP, con `Content-Type: text/plain`.

- `@GetMapping("/greeting")`: registra este método para que responda a peticiones
  `HTTP GET /greeting`. Es un atajo de `@RequestMapping(method = RequestMethod.GET, path = "/greeting")`.
  Spring, internamente, mantiene una tabla de rutas → métodos, y cuando llega una petición GET a
  `/greeting`, la enruta automáticamente a este método (esto lo hace el `DispatcherServlet`, la
  pieza central de Spring MVC que Spring Boot registra solo dentro del Tomcat embebido).

- `@RequestParam(value = "name", defaultValue = "World") String name`: le dice a Spring "toma el
  parámetro de query string llamado `name` (lo que viene después del `?` en la URL, ej.
  `?name=Pedro`) y pásalo como el argumento `name` de este método, convertido automáticamente a
  `String`". Si la petición no incluye `?name=algo` (por ejemplo, si solo se pide `/greeting` a
  secas), Spring usa `"World"` en su lugar gracias a `defaultValue`.

  > **Detalle importante que causó un error real durante el desarrollo:** el atributo se llama
  > **`defaultValue`** (con "V" mayúscula). Escribirlo como `defaultvalue` (todo en minúscula)
  > compila con un error, porque Java es sensible a mayúsculas/minúsculas en los nombres de los
  > atributos de una anotación: el compilador busca un método `defaultvalue()` dentro de la
  > interfaz `@RequestParam` y no lo encuentra.

- `return "Hello, " + name;`: concatenación de strings simple. El resultado es el cuerpo completo
  de la respuesta HTTP.

**Flujo completo de una petición**, para entender cómo se conecta todo esto:

```
Cliente hace GET /greeting?name=Pedro
        ↓
Tomcat embebido recibe la conexión TCP y arma el objeto HttpServletRequest
        ↓
DispatcherServlet (registrado por Spring Boot) busca en su tabla de rutas
        ↓
Encuentra que GET /greeting → HelloRestController.greeting(String)
        ↓
Extrae "Pedro" del query string y lo pasa como argumento `name`
        ↓
Ejecuta el método, obtiene el String "Hello, Pedro"
        ↓
Como la clase es @RestController, escribe ese String directamente como cuerpo de la respuesta
        ↓
Tomcat envía la respuesta HTTP 200 con ese cuerpo de vuelta al cliente
```

---

## 4. `Dockerfile` — empaquetado como imagen de contenedor

```dockerfile
FROM amazoncorretto:21

WORKDIR /app

COPY target/*.jar app.jar

ENV PORT=9000

EXPOSE 9000

ENTRYPOINT [ "java", "-jar", "app.jar" ]
```

- `FROM amazoncorretto:21`: toda imagen Docker se construye **sobre otra imagen base**. Aquí
  partimos de la distribución oficial de Amazon de OpenJDK 21 (Amazon Corretto), que ya trae el
  sistema operativo base (una distribución Linux mínima) más el JDK instalado y configurado. No
  tenemos que instalar Java nosotros mismos.

- `WORKDIR /app`: crea (si no existe) y se posiciona dentro del directorio `/app` **dentro del
  contenedor**. Todas las instrucciones siguientes (`COPY`, y el directorio de trabajo del
  proceso que arranca `ENTRYPOINT`) ocurren relativas a esta carpeta.

- `COPY target/*.jar app.jar`: copia el `.jar` que Maven generó en el host (fuera del contenedor,
  en la carpeta `target/`, producto de correr `mvn clean package` **antes** de construir la
  imagen) hacia adentro del contenedor, renombrándolo a `app.jar`. El patrón `*.jar` funciona
  porque solo hay un `.jar` en `target/` con ese nombre generado por Maven
  (`virtualization-lab-1.0.0.jar`); Docker lo copia sin que tengamos que escribir la versión a
  mano en el Dockerfile (así, si cambia la versión en el `pom.xml`, el Dockerfile no se rompe).

- `ENV PORT=9000`: define una variable de entorno **dentro de la imagen**, con valor por defecto
  `9000`. Esto es lo que hace que, si alguien corre el contenedor sin pasar `-e PORT=...`,
  la aplicación igual reciba `PORT=9000` (que además coincide con el valor por defecto que ya
  tiene el propio código Java en `RestServiceApplication`, así que en la práctica es una
  redundancia intencional: documenta explícitamente en la imagen cuál es el puerto esperado).

- `EXPOSE 9000`: **no abre ningún puerto por sí sola** — es meramente documentación dentro de la
  imagen, que le dice a quien la lea (o a herramientas como `docker inspect`) "este contenedor
  espera tráfico entrante en el puerto 9000". El mapeo real de puertos al host se hace después,
  al ejecutar `docker run -p <puerto-host>:9000 ...`.

- `ENTRYPOINT [ "java", "-jar", "app.jar" ]`: define el **comando que se ejecuta cuando arranca el
  contenedor**. Se usa la forma "exec" (arreglo de strings, en vez de una sola cadena de texto)
  porque así el proceso `java` se convierte directamente en el **PID 1** del contenedor, sin pasar
  por un shell intermedio (`/bin/sh -c "..."`). Esto importa para el manejo de señales: cuando
  Docker hace `docker stop`, envía `SIGTERM` directamente al PID 1 — si hubiera un shell de por
  medio, la señal podría no propagarse correctamente al proceso Java.

---

## 5. `compose.yaml` — orquestación de dos servicios (web + MongoDB)

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: virtualization-web
    environment:
      PORT: 9000
      SPRING_DATA_MONGODB_URI: mongodb://db:27017/workshop
    ports:
      - "8087:9000"
    depends_on:
      - db

  db:
    image: mongo:8
    container_name: virtualization-db
    volumes:
      - mongodb:/data/db
      - mongodb_config:/data/configdb
    ports:
      - "27017:27017"
    command: mongod

volumes:
  mongodb:
  mongodb_config:
```

- `services:`: la raíz del archivo declara qué **servicios** (cada uno, en la práctica, un
  contenedor o grupo de contenedores) forman parte de esta aplicación.

- **Servicio `web`:**
  - `build: { context: ., dockerfile: Dockerfile }`: en vez de usar una imagen ya publicada,
    Compose debe **construir** la imagen localmente usando el `Dockerfile` de este mismo
    directorio (`context: .`) — equivale a correr `docker build .` automáticamente antes de
    levantar el contenedor.
  - `container_name: virtualization-web`: le da un nombre fijo y predecible al contenedor (si no
    se especifica, Docker Compose genera uno automáticamente combinando el nombre del proyecto,
    el servicio y un número).
  - `environment:`: define variables de entorno para el proceso dentro del contenedor.
    `PORT: 9000` fija el puerto de escucha. `SPRING_DATA_MONGODB_URI` está declarada como
    preparación para una futura integración de persistencia (la aplicación **todavía no
    depende** de MongoDB para nada — no hay ninguna dependencia de Spring Data MongoDB en el
    `pom.xml` — así que esta variable, por ahora, es leída por el entorno pero ignorada por la
    aplicación; existe para demostrar cómo se pasaría esta configuración si en el futuro se
    agrega esa dependencia).
  - `ports: - "8087:9000"`: mapea el puerto `9000` del contenedor (donde escucha Spring Boot) al
    puerto `8087` del host. El formato es siempre `"<puerto-host>:<puerto-contenedor>"`.
  - `depends_on: - db`: le dice a Compose "no arranques `web` hasta haber arrancado `db`
    primero". **Importante:** esto controla únicamente el **orden de arranque de los
    contenedores**, no espera a que MongoDB esté realmente listo para aceptar conexiones (para
    eso existiría un `healthcheck`, que aquí no se configuró porque la app no depende
    funcionalmente de Mongo todavía).

- **Servicio `db`:**
  - `image: mongo:8`: en vez de construir una imagen, usa directamente la imagen oficial de
    MongoDB versión 8 publicada en Docker Hub.
  - `volumes: - mongodb:/data/db` y `- mongodb_config:/data/configdb`: monta dos **volúmenes
    nombrados** (gestionados por Docker, no simples carpetas del host) dentro del contenedor, en
    las rutas donde MongoDB guarda sus datos (`/data/db`) y su configuración interna
    (`/data/configdb`). Esto es lo que permite que los datos **sobrevivan** aunque se elimine y
    se vuelva a crear el contenedor (`docker compose down`), y solo se pierdan si explícitamente
    se borran los volúmenes (`docker compose down -v`).
  - `ports: - "27017:27017"`: expone el puerto estándar de MongoDB también en el host, útil para
    poder conectarse desde herramientas externas como MongoDB Compass durante el desarrollo.
  - `command: mongod`: el comando que arranca el servidor de MongoDB dentro del contenedor
    (técnicamente ya es el comando por defecto de esa imagen; se declara explícitamente aquí por
    claridad).

- **`volumes:` (nivel raíz):** declara los nombres `mongodb` y `mongodb_config` como volúmenes
  gestionados por Docker, para que Compose los cree si no existen.

**Cómo se comunican `web` y `db` entre sí:** Docker Compose crea automáticamente una **red
interna** compartida entre todos los servicios de un mismo archivo `compose.yaml`. Dentro de esa
red, cada servicio es alcanzable por **su nombre de servicio** como si fuera un hostname DNS — por
eso la URI `mongodb://db:27017/workshop` funciona: `db` no es una IP fija, es el nombre del
servicio, y Docker resuelve internamente ese nombre a la IP interna real del contenedor de
MongoDB en cada momento.

---

## 6. Resumen de conceptos clave usados en este repositorio

| Concepto | Dónde aparece | Para qué sirve |
|---|---|---|
| Inversión de control / anotaciones | `@SpringBootApplication`, `@RestController` | Spring construye y conecta los objetos por nosotros, en vez de que el programador escriba `new` y cableado manual |
| Configuración por variable de entorno | `System.getenv().getOrDefault(...)` | Que el mismo `.jar`/imagen sirva en local, en un contenedor, o en la nube, sin recompilar |
| Fat JAR | `spring-boot-maven-plugin` | Un único archivo ejecutable, sin depender de un classpath externo |
| Imagen base + capas | `Dockerfile` | Reutilizar un sistema con Java ya instalado en vez de construirlo desde cero |
| PID 1 y señales | `ENTRYPOINT` en forma exec | Que `docker stop` pueda terminar el proceso correctamente |
| Named volumes | `compose.yaml` | Persistencia de datos independiente del ciclo de vida del contenedor |
| DNS interno de Compose | `mongodb://db:27017/...` | Comunicación entre contenedores por nombre de servicio, no por IP fija |
