package com.red;

import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;

import java.net.URI;
import java.util.List;
import java.util.Map;

@Path("/transactions")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class TransactionResource {

    @Inject
    TransactionService transactionService;

    @GET
    public List<Transaction> listTransactions(@QueryParam("accountId") String accountId) {
        return transactionService.list(accountId);
    }

    @GET
    @Path("/{id}")
    public Response getTransaction(@PathParam("id") String id) {
        return transactionService.findById(id)
                .map(transaction -> Response.ok(transaction).build())
                .orElseGet(() -> Response.status(Response.Status.NOT_FOUND)
                        .entity(Map.of("error", "Transaction not found"))
                        .build());
    }

    @POST
    public Response createTransaction(Transaction transaction) {
        try {
            Transaction created = transactionService.create(transaction);
            URI location = UriBuilder.fromPath("/transactions/{id}").build(created.getId());
            return Response.created(location).entity(created).build();
        } catch (IllegalArgumentException exception) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity(Map.of("error", exception.getMessage()))
                    .build();
        } catch (IllegalStateException exception) {
            return Response.status(Response.Status.CONFLICT)
                    .entity(Map.of("error", exception.getMessage()))
                    .build();
        }
    }
}
