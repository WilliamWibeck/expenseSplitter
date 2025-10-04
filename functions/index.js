const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Scheduled settle reminders (daily at 6 PM)
exports.sendSettleReminders = functions.pubsub
  .schedule('0 18 * * *')
  .timeZone('America/New_York')
  .onRun(async (context) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    
    // Get all groups
    const groupsSnapshot = await db.collection('groups').get();
    
    for (const groupDoc of groupsSnapshot.docs) {
      const group = groupDoc.data();
      const groupId = groupDoc.id;
      
      // Get expenses for this group
      const expensesSnapshot = await db
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .get();
      
      const expenses = expensesSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      
      // Compute balances
      const balances = computeBalances(expenses, group.memberUserIds);
      
      // Find users who owe money
      const debtors = Object.entries(balances)
        .filter(([userId, balance]) => balance < -100) // owe more than $1.00
        .map(([userId, balance]) => ({ userId, balance }));
      
      if (debtors.length === 0) continue;
      
      // Get FCM tokens for group members
      const tokens = [];
      for (const userId of group.memberUserIds) {
        const userDoc = await db.collection('users').doc(userId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          if (userData.fcmTokens) {
            tokens.push(...Object.keys(userData.fcmTokens));
          }
        }
      }
      
      if (tokens.length === 0) continue;
      
      // Send reminder
      const message = {
        notification: {
          title: 'Settle up in ' + group.name,
          body: `${debtors.length} member(s) owe money. Time to settle up!`
        },
        data: {
          groupId: groupId,
          type: 'settle_reminder'
        },
        tokens: tokens
      };
      
      try {
        await messaging.sendMulticast(message);
        console.log(`Sent reminder for group ${groupId} to ${tokens.length} tokens`);
      } catch (error) {
        console.error('Error sending reminder:', error);
      }
    }
  });

// Manual reminder trigger (HTTP)
exports.sendGroupReminder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }
  
  const { groupId } = data;
  if (!groupId) {
    throw new functions.https.HttpsError('invalid-argument', 'groupId is required');
  }
  
  const db = admin.firestore();
  const messaging = admin.messaging();
  
  // Get group
  const groupDoc = await db.collection('groups').doc(groupId).get();
  if (!groupDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Group not found');
  }
  
  const group = groupDoc.data();
  
  // Check if user is member
  if (!group.memberUserIds.includes(context.auth.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Not a group member');
  }
  
  // Get FCM tokens for group members
  const tokens = [];
  for (const userId of group.memberUserIds) {
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      if (userData.fcmTokens) {
        tokens.push(...Object.keys(userData.fcmTokens));
      }
    }
  }
  
  if (tokens.length === 0) {
    return { success: false, message: 'No FCM tokens found' };
  }
  
  // Send reminder
  const message = {
    notification: {
      title: 'Settle up in ' + group.name,
      body: 'Someone requested a settlement reminder for this group'
    },
    data: {
      groupId: groupId,
      type: 'manual_reminder'
    },
    tokens: tokens
  };
  
  try {
    await messaging.sendMulticast(message);
    return { success: true, tokensSent: tokens.length };
  } catch (error) {
    console.error('Error sending manual reminder:', error);
    throw new functions.https.HttpsError('internal', 'Failed to send reminder');
  }
});

// Helper function to compute balances
function computeBalances(expenses, memberUserIds) {
  const balances = {};
  
  // Initialize balances
  for (const userId of memberUserIds) {
    balances[userId] = 0;
  }
  
  // Process expenses
  for (const expense of expenses) {
    const amountPerPerson = Math.floor(expense.amountCents / expense.splitUserIds.length);
    
    // Person who paid gets credited
    balances[expense.paidByUserId] += expense.amountCents;
    
    // Everyone who split gets debited
    for (const userId of expense.splitUserIds) {
      balances[userId] -= amountPerPerson;
    }
  }
  
  return balances;
}


