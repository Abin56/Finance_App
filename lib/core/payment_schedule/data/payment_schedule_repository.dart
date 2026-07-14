import '../../data/firestore_crud_repository.dart';
import '../../errors/app_exception.dart';
import '../../utils/id_generator.dart';
import '../domain/owner_type.dart';
import '../domain/payment_schedule.dart';
import '../domain/schedule_type.dart';

/// Schedule-specific persistence on top of the generic CRUD/soft-delete
/// repository. Never mutates on payment — only its child `Installment`
/// documents do (see `InstallmentRepository`).
class PaymentScheduleRepository extends FirestoreCrudRepository<PaymentSchedule> {
  PaymentScheduleRepository(super.collection);

  Future<PaymentSchedule> createSchedule({
    required OwnerType ownerType,
    required String ownerId,
    required double totalAmount,
    required ScheduleType scheduleType,
    required DateTime firstDueDate,
    int? customIntervalDays,
    int? installmentCount,
    String notes = '',
  }) async {
    if (totalAmount <= 0) {
      throw const AppException('Total amount must be greater than 0');
    }
    if (scheduleType == ScheduleType.custom && (customIntervalDays == null || customIntervalDays <= 0)) {
      throw const AppException('Custom schedules need a repeat interval greater than 0 days');
    }

    final schedule = PaymentSchedule(
      id: IdGenerator.generate(),
      ownerType: ownerType,
      ownerId: ownerId,
      totalAmount: totalAmount,
      scheduleType: scheduleType,
      firstDueDate: firstDueDate,
      customIntervalDays: scheduleType == ScheduleType.custom ? customIntervalDays : null,
      installmentCount: installmentCount,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await add(schedule.id, schedule);
    return schedule;
  }

  Future<void> editSchedule(
    PaymentSchedule schedule, {
    double? totalAmount,
    DateTime? firstDueDate,
    String? notes,
    int? installmentCount,
  }) async {
    if (totalAmount != null && totalAmount <= 0) {
      throw const AppException('Total amount must be greater than 0');
    }
    if (installmentCount != null && installmentCount < 1) {
      throw const AppException('Schedule needs at least 1 installment');
    }
    schedule.updateField(
      field: 'totalAmount',
      oldValue: schedule.totalAmount,
      newValue: totalAmount,
      apply: (v) => schedule.totalAmount = v,
    );
    schedule.updateField(
      field: 'firstDueDate',
      oldValue: schedule.firstDueDate,
      newValue: firstDueDate,
      apply: (v) => schedule.firstDueDate = v,
    );
    schedule.updateField(
      field: 'notes',
      oldValue: schedule.notes,
      newValue: notes,
      apply: (v) => schedule.notes = v,
    );
    schedule.updateField(
      field: 'installmentCount',
      oldValue: schedule.installmentCount,
      newValue: installmentCount,
      apply: (v) => schedule.installmentCount = v,
    );
    await update(schedule);
  }
}
