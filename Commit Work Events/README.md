
## COMMIT/ROLLBACK Work Events

When a transaction is finished the data is either persisted or rolled back using the commands- COMMIT WORK ( & WAIT) or ROLLBACK WORK.

Many times we may need to react after the such commands- commit/rollback to do some other actions. But how to know if it is committed/rolled back?

The command COMMIT WORK ( & WAIT) or ROLLBACK WORK always triggers an event – TRANSACTION_FINISHED of class CL_SYSTEM_TRANSACTION_STATE which exports a parameter KIND whose value is either C ( committed) / R ( rolled back). We can register for this event and react on it.


![image](https://user-images.githubusercontent.com/87908849/153699203-1af05c6b-2a44-4afd-8443-ec1279c4e68d.png)

**Execution Output**

![image](https://user-images.githubusercontent.com/87908849/153699224-cbd57efd-bfc5-4b81-8cc0-153181ea7557.png)





#### Other useful methods in CL_SYSTEM_TRANSACTION_STATE class:

![image](https://user-images.githubusercontent.com/87908849/153699240-3b496bdf-5d88-4bb3-93d6-b50dc9eca1a2.png)
