/**
 * Cloud Functions for MarkaAI Notification System
 * Automated email and push notifications for appointment reminders
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as nodemailer from 'nodemailer';

admin.initializeApp();

// SendGrid or SMTP Configuration
// TODO: Replace with your SendGrid API key or SMTP credentials
const transporter = nodemailer.createTransport({
  service: 'gmail', // Or use SendGrid
  auth: {
    user: functions.config().email.user, // Set via: firebase functions:config:set email.user="your@email.com"
    pass: functions.config().email.password, // Set via: firebase functions:config:set email.password="yourpassword"
  },
});

/**
 * Scheduled function that runs daily at 9:00 AM (Brazil timezone)
 * Checks for upcoming appointments and sends reminders
 */
export const checkUpcomingAppointments = functions
  .region('us-central1')
  .pubsub.schedule('every day 09:00')
  .timeZone('America/Sao_Paulo')
  .onRun(async (context) => {
    console.log('Starting appointment reminder check...');

    const now = new Date();
    const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    try {
      // Get all upcoming appointments in the next 7 days
      const appointmentsSnapshot = await admin
        .firestore()
        .collection('appointments')
        .where('data_agendamento', '>=', admin.firestore.Timestamp.fromDate(now))
        .where('data_agendamento', '<=', admin.firestore.Timestamp.fromDate(sevenDaysFromNow))
        .where('status', '!=', 'cancelado')
        .get();

      console.log(`Found ${appointmentsSnapshot.size} upcoming appointments`);

      const notificationPromises: Promise<void>[] = [];

      for (const appointmentDoc of appointmentsSnapshot.docs) {
        const appointment = appointmentDoc.data();
        const appointmentId = appointmentDoc.id;

        // Skip if notification already sent
        if (appointment.notification_sent) {
          continue;
        }

        // Get client and shop data
        const clientId = appointment.clientId;
        const shopId = appointment.shopId;

        if (!clientId || !shopId) continue;

        const [clientDoc, shopDoc] = await Promise.all([
          admin.firestore().collection('users').doc(clientId).get(),
          admin.firestore().collection('shops').doc(shopId).get(),
        ]);

        if (!clientDoc.exists || !shopDoc.exists) continue;

        const client = clientDoc.data()!;
        const shop = shopDoc.data()!;

        // Check if shop has reminders enabled
        const shopSettings = shop.notification_settings || {};
        if (shopSettings.send_reminders === false) {
          continue;
        }

        // Get reminder preferences
        const clientPrefs = client.notification_preferences || {};
        const clientReminderDays = clientPrefs.reminder_days_before || 3;
        const shopReminderDays = shopSettings.default_reminder_days || 3;
        
        // Use client preference if set, otherwise shop default
        const reminderDays = clientReminderDays;

        // Calculate days until appointment
        const appointmentDate = appointment.data_agendamento.toDate();
        const daysUntil = Math.floor(
          (appointmentDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
        );

        // Check if it's time to send the reminder
        if (daysUntil === reminderDays) {
          notificationPromises.push(
            sendAppointmentReminder(
              appointmentId,
              appointment,
              client,
              shop
            )
          );
        }
      }

      await Promise.all(notificationPromises);
      console.log(`Sent ${notificationPromises.length} reminders`);

      return null;
    } catch (error) {
      console.error('Error checking appointments:', error);
      throw error;
    }
  });

/**
 * Send email and push notification reminder for an appointment
 */
async function sendAppointmentReminder(
  appointmentId: string,
  appointment: any,
  client: any,
  shop: any
): Promise<void> {
  const clientPrefs = client.notification_preferences || {};
  const emailEnabled = clientPrefs.email_enabled !== false;
  const pushEnabled = clientPrefs.push_enabled !== false;

  const clientName = client.nome || 'Cliente';
  const clientEmail = client.email;
  const serviceName = appointment.servico_nome || appointment.servico || 'Serviço';
  const shopName = shop.nome || 'Estabelecimento';
  
  const appointmentDate = appointment.data_agendamento.toDate();
  const formattedDate = appointmentDate.toLocaleDateString('pt-BR', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
  const formattedTime = appointment.hora || appointmentDate.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });

  try {
    // Send Email
    if (emailEnabled && clientEmail) {
      await sendEmail(
        clientEmail,
        clientName,
        serviceName,
        shopName,
        formattedDate,
        formattedTime
      );
    }

    // Send Push Notification
    if (pushEnabled && client.fcmToken) {
      await sendPushNotification(
        client.fcmToken,
        serviceName,
        formattedDate,
        formattedTime,
        appointmentId,
        shop.id
      );
    }

    // Mark notification as sent
    await admin.firestore().collection('appointments').doc(appointmentId).update({
      notification_sent: true,
      notification_sent_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log notification
    await admin.firestore().collection('notification_logs').add({
      appointment_id: appointmentId,
      client_id: client.id,
      shop_id: shop.id,
      email_sent: emailEnabled && !!clientEmail,
      push_sent: pushEnabled && !!client.fcmToken,
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
      status: 'sent',
    });

    console.log(`Reminder sent for appointment ${appointmentId}`);
  } catch (error) {
    console.error(`Error sending reminder for ${appointmentId}:`, error);
    
    // Log error
    await admin.firestore().collection('notification_logs').add({
      appointment_id: appointmentId,
      client_id: client.id,
      shop_id: shop.id,
      status: 'failed',
      error_message: error instanceof Error ? error.message : String(error),
      sent_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    throw error;
  }
}

/**
 * Send email reminder
 */
async function sendEmail(
  to: string,
  clientName: string,
  serviceName: string,
  shopName: string,
  date: string,
  time: string
): Promise<void> {
  const mailOptions = {
    from: '"MarkaAI" <noreply@markaai.com>',
    to,
    subject: 'Lembrete de Agendamento - MarkaAI 📅',
    html: `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: white; padding: 30px; border: 1px solid #e0e0e0; }
          .details { background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; }
          .detail-item { margin: 10px 0; }
          .detail-label { font-weight: bold; color: #667eea; }
          .footer { background: #f9f9f9; padding: 20px; text-align: center; font-size: 12px; color: #666; border-radius: 0 0 10px 10px; }
          .button { background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; display: inline-block; margin: 20px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1 style="margin: 0;">🔔 Lembrete de Agendamento</h1>
          </div>
          <div class="content">
            <p>Olá <strong>${clientName}</strong>,</p>
            <p>Este é um lembrete do seu agendamento próximo:</p>
            
            <div class="details">
              <div class="detail-item">
                <span class="detail-label">Serviço:</span> ${serviceName}
              </div>
              <div class="detail-item">
                <span class="detail-label">Local:</span> ${shopName}
              </div>
              <div class="detail-item">
                <span class="detail-label">Data:</span> ${date}
              </div>
              <div class="detail-item">
                <span class="detail-label">Horário:</span> ${time}
              </div>
            </div>
            
            <p style="text-align: center;">
              <a href="markaai://appointments" class="button">Ver no App</a>
            </p>
            
            <p>Nos vemos em breve! 👋</p>
          </div>
          <div class="footer">
            <p>Para cancelar ou reagendar, acesse o app MarkaAI</p>
            <p style="margin-top: 10px; color: #999;">
              Este é um email automático, por favor não responda.
            </p>
          </div>
        </div>
      </body>
      </html>
    `,
  };

  await transporter.sendMail(mailOptions);
  console.log(`Email sent to ${to}`);
}

/**
 * Send push notification
 */
async function sendPushNotification(
  fcmToken: string,
  serviceName: string,
  date: string,
  time: string,
  appointmentId: string,
  shopId: string
): Promise<void> {
  const message = {
    token: fcmToken,
    notification: {
      title: 'Lembrete de Agendamento 📅',
      body: `${serviceName} em ${date} às ${time}`,
    },
    data: {
      type: 'appointment_reminder',
      appointment_id: appointmentId,
      shop_id: shopId,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    android: {
      priority: 'high' as const,
      notification: {
        sound: 'default',
        channelId: 'appointments',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
  };

  await admin.messaging().send(message);
  console.log(`Push notification sent to token ending in ${fcmToken.slice(-10)}`);
}

/**
 * Manual test function (callable via app)
 * Usage: Call this to test the notification system
 */
export const testNotificationSystem = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
  }

  // Trigger the scheduled function manually
  await checkUpcomingAppointments(null as any);

  return { success: true, message: 'Test notification check completed' };
});
