#Desde donde se quiere iniciar la imagen docker FROM imagen:version
FROM amazoncorretto:21  

#Este es el directorio de trabajo dentro del contendor  "cd/ app"
WORKDIR /app

#Esto hace una copia de los archivos mencionados al directorio /app dentro del contenedor "COPY [archivo_de_origen] [archivo_de_destino]"
COPY target/*.jar app.jar

#Este muestra el puerto que va a estar usando la aplicacion
EXPOSE 6000

#Esto le dice al contendor que ejecute el archivo app.jar y es el comando principal, mientras que CMD usa argumentos por defecto
ENTRYPOINT [ "java", "-jar", "app.jar" ]