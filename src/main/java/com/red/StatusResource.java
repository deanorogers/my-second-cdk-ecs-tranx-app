package com.red;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@Path("/")
public class StatusResource {

    @ConfigProperty(name = "prod.quarkus.instance-name")
    String instanceName;

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    public Response status() {
        return Response.ok()
                .entity("quarkus transactions service is running\n")
                .build();
    }
}
