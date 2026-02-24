class FirestoreContract {
  static const users = 'users';
}

class UserSubcollections {
  static const items = 'items';
  static const profile = 'profile';
  static const settings = 'settings';
}

class SingletonDocs {
  static const defaultDoc = 'default';
}

class ItemStatus {
  static const pending = 'pending';
  static const keep = 'keep';
  static const returnItem = 'return';
  static const expired = 'expired';

  static const all = [pending, keep, returnItem, expired];
}

class ItemSource {
  static const manual = 'manual';
  static const gmailSync = 'gmail_sync';

  static const all = [manual, gmailSync];
}

class StoreType {
  static const amazon = 'amazon';
  static const shein = 'shein';
  static const other = 'other';

  static const all = [amazon, shein, other];
}

class ItemFields {
  static const uid = 'uid';
  static const title = 'title';
  static const store = 'store';
  static const status = 'status';
  static const deliveredAt = 'deliveredAt';
  static const returnDeadline = 'returnDeadline';
  static const returnWindowDays = 'returnWindowDays';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
  static const orderId = 'orderId';
  static const normalizedTitle = 'normalizedTitle';
  static const source = 'source';
  static const messageIds = 'messageIds';
  static const notes = 'notes';
}

class ProfileFields {
  static const uid = 'uid';
  static const displayName = 'displayName';
  static const email = 'email';
  static const photoUrl = 'photoUrl';
  static const timezone = 'timezone';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
}

class SettingsFields {
  static const uid = 'uid';
  static const defaultReturnWindowDays = 'defaultReturnWindowDays';
  static const amazonReturnWindowDays = 'amazonReturnWindowDays';
  static const sheinReturnWindowDays = 'sheinReturnWindowDays';
  static const remindersEnabled = 'remindersEnabled';
  static const reminderOffsetsDays = 'reminderOffsetsDays';
  static const gmailSyncEnabled = 'gmailSyncEnabled';
  static const calendarExportEnabled = 'calendarExportEnabled';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
}
