package com.red;

import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicInteger;

@ApplicationScoped
public class TransactionService {

    private final ConcurrentMap<String, Transaction> transactions = new ConcurrentHashMap<>();
    private final AtomicInteger nextId = new AtomicInteger(90000);

    @PostConstruct
    void init() {
        add("t-1001", "1001", "CREDIT", "2500.00", "Salary", "2026-10-01T09:00:00Z");
        add("t-1002", "1001", "DEBIT", "64.50", "Groceries", "2026-10-03T17:42:00Z");
        add("t-1003", "1001", "DEBIT", "900.00", "Rent", "2026-10-05T08:00:00Z");
        add("t-2001", "2001", "CREDIT", "500.00", "Monthly savings transfer", "2026-10-06T10:00:00Z");
        add("t-2002", "2001", "CREDIT", "12.34", "Interest", "2026-10-31T23:59:00Z");
        add("t-3001", "3001", "CREDIT", "1000.00", "Fund contribution", "2026-10-15T12:00:00Z");
    }

    private void add(String id, String accountId, String type, String amount, String description, String timestamp) {
        transactions.put(id, new Transaction(id, accountId, type, new BigDecimal(amount), "USD",
                description, Instant.parse(timestamp)));
    }

    public List<Transaction> list(String accountId) {
        String filter = normalize(accountId);
        return transactions.values().stream()
                .filter(t -> filter == null || t.getAccountId().equals(filter))
                .sorted(Comparator.comparing(Transaction::getTimestamp).thenComparing(Transaction::getId))
                .map(this::copy)
                .toList();
    }

    public Optional<Transaction> findById(String id) {
        return Optional.ofNullable(transactions.get(id)).map(this::copy);
    }

    public Transaction create(Transaction request) {
        if (request == null) {
            throw new IllegalArgumentException("Transaction payload is required");
        }

        String accountId = normalize(request.getAccountId());
        String type = normalize(request.getType());
        String currency = normalize(request.getCurrency());
        BigDecimal amount = request.getAmount();

        if (accountId == null || type == null || currency == null || amount == null) {
            throw new IllegalArgumentException("Transaction accountId, type, amount, and currency are required");
        }

        type = type.toUpperCase(Locale.ROOT);
        if (!type.equals("CREDIT") && !type.equals("DEBIT")) {
            throw new IllegalArgumentException("Transaction type must be CREDIT or DEBIT");
        }
        if (amount.signum() <= 0) {
            throw new IllegalArgumentException("Transaction amount must be positive");
        }

        String id = normalize(request.getId());
        if (id == null) {
            id = "t-" + nextId.incrementAndGet();
        }

        Instant timestamp = request.getTimestamp() != null ? request.getTimestamp() : Instant.now();
        Transaction transaction = new Transaction(id, accountId, type, amount,
                currency.toUpperCase(Locale.ROOT), normalize(request.getDescription()), timestamp);

        if (transactions.putIfAbsent(id, transaction) != null) {
            throw new IllegalStateException("Transaction with id '" + id + "' already exists");
        }
        return copy(transaction);
    }

    private Transaction copy(Transaction t) {
        return new Transaction(t.getId(), t.getAccountId(), t.getType(), t.getAmount(),
                t.getCurrency(), t.getDescription(), t.getTimestamp());
    }

    private String normalize(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
