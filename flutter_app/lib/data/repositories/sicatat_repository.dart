import '../models/app_user.dart';
import '../models/master_data_models.dart';
import '../models/sheet_model.dart';

/// Contract for the production data layer.
///
/// Implementations preserve the existing Supabase schema and local SQLite
/// queue, while widgets only receive explicitly typed domain objects.
abstract interface class SicatatRepository {
  Future<AppUser> signIn({required String nik, required String pin});
  Future<AppUser?> restoreSession();
  Future<List<ShiftOption>> getActiveShifts();
  Future<TemperatureTemplate> getActiveTemperatureTemplate();
  Future<List<MeasurementPoint>> getGearboxMeasurementPoints();
  Future<InspectionFormConfig> getInspectionFormConfig();
  Future<List<SheetModel>> listSheets();
  Future<List<SheetModel>> listSharedSheets({
    String? teamId,
    String? createdBy,
  });
  Future<SheetModel> createSheet(CreateSheetCommand command);
  Future<void> syncPending();
}
