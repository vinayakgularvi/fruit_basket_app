/// Customers list filter (chips + deep links from Home / add-customer flow).
enum CustomerListFilter {
  all,
  morning,
  evening,
  activeOnly,
  inactiveOnly,
  createdPendingApproval,
  lastDayOfPlan,
  /// Soft-deleted in the last 30 days (restore or wait for auto-purge).
  recentlyDeleted,
}
