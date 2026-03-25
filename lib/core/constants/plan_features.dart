// lib/core/constants/plan_features.dart

enum PlanKey { free, starter, plus, pro }


class PlanFeatures {
  // Agendamento
  final bool onlineBooking;
  final bool canDisableOnlineBooking;
  final bool agendaInterval;
  final bool clientChoosesProfessional;
  final bool agendaOptimization;

  // Financeiro
  final bool financialTab;
  final bool financialDashboard;

  // Pagamentos
  final bool mercadoPagoIntegration;
  final List<String> payments;
  final bool requireDeposit;

  // Profissionais e mídia
  final int maxProfessionals;
  final int maxPhotosPerService;

  // Clientes
  final bool clientClassification;
  final bool clientFilter;
  final bool clientBlock;

  // Marketing e automações
  final bool coupons;
  final bool birthdayDiscount;
  final bool automationClientGone;
  final bool automationClientSawNoBook;

  // Estoque
  final bool stockManagement;

  // Infraestrutura
  final bool boosting;
  final bool googleBackup;
  final bool googleBusiness;
  final bool automaticPriceAdjustment;

  // Equipe
  final bool commissionView;

  // Folgas e Feriados
  final bool holidaysManagement;
  final bool customHolidays;

  const PlanFeatures({
    required this.onlineBooking,
    required this.canDisableOnlineBooking,
    required this.agendaInterval,
    required this.clientChoosesProfessional,
    required this.agendaOptimization,
    required this.financialTab,
    required this.financialDashboard,
    required this.mercadoPagoIntegration,
    required this.payments,
    required this.requireDeposit,
    required this.maxProfessionals,
    required this.maxPhotosPerService,
    required this.clientClassification,
    required this.clientFilter,
    required this.clientBlock,
    required this.coupons,
    required this.birthdayDiscount,
    required this.automationClientGone,
    required this.automationClientSawNoBook,
    required this.stockManagement,
    required this.boosting,
    required this.googleBackup,
    required this.googleBusiness,
    required this.automaticPriceAdjustment,
    required this.commissionView,
    required this.holidaysManagement,
    required this.customHolidays,
  });
}

const Map<PlanKey, PlanFeatures> planFeaturesConfig = {
  PlanKey.free: PlanFeatures(
    onlineBooking: true,
    canDisableOnlineBooking: true,
    agendaInterval: true,
    clientChoosesProfessional: false,
    agendaOptimization: false,
    financialTab: false,
    financialDashboard: false,
    mercadoPagoIntegration: false,
    payments: ['in_person'],
    requireDeposit: false,
    maxProfessionals: 1,
    maxPhotosPerService: 1,
    clientClassification: false,
    clientFilter: false,
    clientBlock: false,
    coupons: false,
    birthdayDiscount: false,
    automationClientGone: false,
    automationClientSawNoBook: false,
    stockManagement: false,
    boosting: true,
    googleBackup: true,
    googleBusiness: true,
    automaticPriceAdjustment: false,
    commissionView: false,
    holidaysManagement: false,
    customHolidays: false,
  ),
  PlanKey.starter: PlanFeatures(
    onlineBooking: true,
    canDisableOnlineBooking: true,
    agendaInterval: true,
    clientChoosesProfessional: true,
    agendaOptimization: true,
    financialTab: true,
    financialDashboard: false,
    mercadoPagoIntegration: true,
    payments: ['in_person', 'pix'],
    requireDeposit: true,
    maxProfessionals: 2,
    maxPhotosPerService: 3,
    clientClassification: false,
    clientFilter: false,
    clientBlock: false,
    coupons: false,
    birthdayDiscount: true,
    automationClientGone: false,
    automationClientSawNoBook: false,
    stockManagement: false,
    boosting: true,
    googleBackup: true,
    googleBusiness: true,
    automaticPriceAdjustment: false,
    commissionView: true,
    holidaysManagement: false,
    customHolidays: false,
  ),
  PlanKey.plus: PlanFeatures(
    onlineBooking: true,
    canDisableOnlineBooking: true,
    agendaInterval: true,
    clientChoosesProfessional: true,
    agendaOptimization: true,
    financialTab: true,
    financialDashboard: true,
    mercadoPagoIntegration: true,
    payments: ['in_person', 'pix', 'credit_card', 'debit_card'],
    requireDeposit: true,
    maxProfessionals: 3,
    maxPhotosPerService: 5,
    clientClassification: true,
    clientFilter: true,
    clientBlock: true,
    coupons: true,
    birthdayDiscount: true,
    automationClientGone: true,
    automationClientSawNoBook: true,
    stockManagement: true,
    boosting: true,
    googleBackup: true,
    googleBusiness: true,
    automaticPriceAdjustment: true,
    commissionView: true,
    holidaysManagement: true,
    customHolidays: false,
  ),
  PlanKey.pro: PlanFeatures(
    onlineBooking: true,
    canDisableOnlineBooking: true,
    agendaInterval: true,
    clientChoosesProfessional: true,
    agendaOptimization: true,
    financialTab: true,
    financialDashboard: true,
    mercadoPagoIntegration: true,
    payments: ['in_person', 'pix', 'credit_card', 'debit_card'],
    requireDeposit: true,
    maxProfessionals: 5,
    maxPhotosPerService: 5,
    clientClassification: true,
    clientFilter: true,
    clientBlock: true,
    coupons: true,
    birthdayDiscount: true,
    automationClientGone: true,
    automationClientSawNoBook: true,
    stockManagement: true,
    boosting: true,
    googleBackup: true,
    googleBusiness: true,
    automaticPriceAdjustment: true,
    commissionView: true,
    holidaysManagement: true,
    customHolidays: true,
  ),
};
